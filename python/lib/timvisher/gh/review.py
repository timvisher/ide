import json
import pathlib
import sys

from timvisher import aictl
from timvisher.gh import comment, fetch, nouns, pr, record, state, store, sync, targets
from timvisher.gh.errors import ERROR, USAGE, fail, usage

USAGE_TEXT = """\
Usage: timvisher_gh [-C <path>] review delete [--force] [--plan] [<target>]
       timvisher_gh [-C <path>] review dismiss [--force] [--plan] <target> <message-file>
       timvisher_gh [-C <path>] review push [--plan] <target>
       timvisher_gh [-C <path>] review info <target> [<component>]

  delete [<target>]          delete a pending (unsubmitted) review of yours, and
                             its draft comments, then archive any copy of ours. A
                             review URL names it; a PR target (or none: the
                             worktree's PR) means your pending review there.
                             Prompts unless --force; --force refuses someone else's
                             review. Submitted reviews can't be deleted.
  dismiss <target> <message-file>
                             dismiss a submitted APPROVED or CHANGES_REQUESTED review,
                             permanently. <message-file> (non-empty) moves into the
                             review's store directory as dismissal.md, leaving a
                             symlink, and DISMISSED becomes the review's wanted
                             state, which push applies; rerunning reports 'already
                             dismissed'. Needs write access to the repository.
                             Prompts unless --force; --force refuses someone else's
                             review.
  push <target>              apply the review's wanted state, if GitHub doesn't
                             already have it
  info <target> [<component>]  the record (see 'review info --help')

A review's <target> is its https://github.com/O/R/pull/N#pullrequestreview-<ID>
URL, or a file in its store directory.
"""

DISMISSABLE = ("APPROVED", "CHANGES_REQUESTED")
MESSAGE = "dismissal.md"


def _parse(args):
    flags = {"force": False, "plan": False}
    positionals = []
    for arg in args:
        match arg:
            case "-h" | "--help":
                sys.stdout.write(USAGE_TEXT)
                return None
            case "--force" | "-f":
                flags["force"] = True
            case "--plan":
                flags["plan"] = True
            case _ if arg.startswith("-"):
                usage(f"review: unknown option '{arg}'", "See 'timvisher_gh review --help'")
            case _:
                positionals.append(arg)
    return positionals, flags


def _endpoint(found, review_id):
    spec = f"{found.owner}/{found.repo}"
    return spec, f"repos/{spec}/pulls/{found.number}/reviews/{review_id}"


def _archive(opened, url, now):
    found = store.live(opened.db, url)
    if found is not None:
        with opened.write() as db:
            store.archive(db, found["id"], now)
            opened.touch(found["id"])


def _write_access(spec):
    permissions = fetch.api(spec, f"repos/{spec}").get("permissions") or {}
    return any(permissions.get(name) for name in ("push", "maintain", "admin"))


def _pending(found, viewer):
    spec = f"{found.owner}/{found.repo}"
    return next((r for r in fetch.api(spec, "--paginate", f"repos/{spec}/pulls/{found.number}/reviews")
                 if r["state"] == "PENDING" and r["user"]["login"].lower() == viewer.lower()), None)


def delete(opened, context, positionals, flags, now):
    if 1 < len(positionals):
        usage("review delete takes at most one <target>")
    found = targets.resolve("review", positionals[0] if positionals else None, context=context, db=opened.db)
    if found.kind not in ("review", "pr"):
        usage(f"'{found.url}' names a {found.kind}, so review delete can't use it.")
    spec = f"{found.owner}/{found.repo}"
    viewer = fetch.api(spec, "user")["login"]
    if found.kind == "pr":
        pending = _pending(found, viewer)
        if pending is None:
            aictl.info(code="timvisher_gh_already_deleted", message=f"You have no pending review on {found.pr_url}.")
            return 0
        found = targets.Target("review", owner=found.owner, repo=found.repo, number=found.number,
                               review_id=pending["id"])
    spec, endpoint = _endpoint(found, found.review_id)
    try:
        review = fetch.api(spec, endpoint)
    except fetch.NotFound:
        if not flags["plan"]:
            _archive(opened, found.url, now)
        aictl.info(code="timvisher_gh_already_deleted", message=f"{found.url} is already gone from GitHub.")
        return 0
    if review["state"] != "PENDING":
        fail("timvisher_gh_review_submitted",
             f"{found.url} is a submitted {review['state']} review, and GitHub deletes only pending ones.",
             suggestions=[f"Dismiss it instead: 'timvisher_gh review dismiss {found.url} <message-file>'"]
             if review["state"] in DISMISSABLE else [])
    author = review["user"]["login"]
    theirs = author.lower() != viewer.lower()
    if flags["force"] and theirs:
        fail("timvisher_gh_delete_not_yours", f"{found.url} is {author}'s review, so --force won't delete it.",
             status=USAGE, suggestions=["Rerun without --force to confirm deleting someone else's review"])
    if flags["plan"]:
        print(f"- review  {found.url}  delete")
        return 0
    by = f" by {author}" if theirs else ""
    if not flags["force"] and not nouns.confirm(f"Delete the pending review {found.url}{by} and its draft comments?"):
        aictl.info(code="timvisher_gh_delete_skipped", message=f"Kept {found.url}.")
        return 0
    fetch.api(spec, "-X", "DELETE", endpoint)
    try:
        fetch.api(spec, endpoint)
    except fetch.NotFound:
        _archive(opened, found.url, now)
        aictl.info(code="timvisher_gh_deleted", message=f"Deleted {found.url}.")
        return 0
    fail("timvisher_gh_delete_unconfirmed", f"GitHub still shows {found.url} after deleting it; our copy is kept.",
         suggestions=["Rerun the delete"])


class ReviewAdapter:
    managed = ("state",)

    def __init__(self, opened, now):
        self.state = opened
        self.now = now

    def _endpoint(self, item):
        url = self.state.db.execute("SELECT url FROM objects WHERE id = ?", (item.object_id,)).fetchone()[0]
        found = targets.parse_url(url, "review")
        return _endpoint(found, found.review_id)

    def fetch(self, item):
        spec, endpoint = self._endpoint(item)
        found = fetch.api(spec, endpoint)
        self.state.db.execute("UPDATE raw SET payload = ?, fetched_at = ? WHERE object_id = ?",
                              (json.dumps(found), self.now, item.object_id))
        return {"state": found["state"]}

    def read_source(self, item):
        wanted = pr.source_state(self.state.db, item.object_id).get("state")
        return None if wanted is None else {"state": wanted}

    def write_source(self, item, values):
        pr.set_source_state(self.state.db, item.object_id, {"state": values["state"]}, self.now)

    def push(self, item, values):
        if values["state"] != "DISMISSED":
            fail("timvisher_gh_review_state_unsupported",
                 f"{item.url} can only be dismissed, not moved to {values['state']}.")
        message = sync.normalize(_message_file(self.state.db, item.object_id).read_text(encoding="utf-8"))
        spec, endpoint = self._endpoint(item)
        fetch.api(spec, "-X", "PUT", f"{endpoint}/dismissals", "-f", f"message={message}", "-f", "event=DISMISS")


def _message_file(db, object_id):
    return store.store_file(db, object_id).parent / MESSAGE


def _review(opened, found, now):
    object_id = comment._object(opened, found, now)
    spec, endpoint = _endpoint(found, found.review_id)
    try:
        review = fetch.api(spec, endpoint)
    except fetch.NotFound:
        fail("timvisher_gh_not_found", f"GitHub has no review at {found.url}.",
             suggestions=["Check the URL, and that your gh account can see the repository"])
    if review["state"] == "PENDING":
        fail("timvisher_gh_review_not_dismissable", f"{found.url} is a pending review; only submitted ones can be "
             "dismissed.", suggestions=[f"Delete it instead: 'timvisher_gh review delete {found.url}'"])
    if object_id is None:
        fail("timvisher_gh_not_found", f"GitHub lists no review at {found.url} on {found.pr_url}.",
             suggestions=[f"Run 'timvisher_gh pr pull {found.pr_url}', then rerun"])
    return object_id, review


def _record_state(opened, object_id, review, now):
    with opened.write() as db:
        store.set_remote(db, object_id, "state", review["state"], now)
        db.execute("UPDATE raw SET payload = ?, fetched_at = ? WHERE object_id = ?",
                   (json.dumps(review), now, object_id))
        opened.touch(object_id)


def _apply(opened, found, object_id, flags, now):
    rc = sync.Engine(opened, "push", now=now, rerun=f"timvisher_gh review push {found.url}",
                     plan_only=flags["plan"]).run([sync.Item(object_id, "review", found.url, ReviewAdapter(opened, now))])
    if rc != 0 or flags["plan"]:
        return rc
    current = json.loads(opened.db.execute("SELECT remote FROM fields WHERE object_id = ? AND name = 'state'",
                                           (object_id,)).fetchone()[0])
    if current != "DISMISSED":
        aictl.error(code="timvisher_gh_dismiss_failed", message=f"{found.url} is still {current} after asking "
                    "GitHub to dismiss it.", suggestions=[f"Rerun: 'timvisher_gh review push {found.url}'"])
        return ERROR
    aictl.info(code="timvisher_gh_dismissed", message=f"Dismissed {found.url}.")
    print(found.url)
    return 0


def _already(opened, found, object_id, review, plan, now):
    _record_state(opened, object_id, review, now)
    if plan:
        print(f"  review  {found.url}  unchanged: already dismissed")
    else:
        aictl.info(code="timvisher_gh_already_dismissed", message=f"{found.url} is already dismissed.")
        print(found.url)
    return 0


def _resolve_review(opened, context, target, verb):
    found = targets.resolve("review", target, context=context, db=opened.db)
    if found.kind != "review":
        usage(f"'{found.url}' names a {found.kind}, so review {verb} can't use it.",
              "Pass the review's #pullrequestreview-<ID> URL")
    return found


def dismiss(opened, context, positionals, flags, now):
    if len(positionals) != 2:
        usage("review dismiss needs a <target> and a <message-file>")
    target, message_arg = positionals
    source = pathlib.Path(message_arg)
    if not source.is_file():
        usage(f"'{message_arg}' isn't a file; the dismissal message is a file, like a comment's body.")
    if not sync.normalize(source.read_text(encoding="utf-8")).strip():
        usage(f"'{message_arg}' is empty, and GitHub needs a message to dismiss a review.")
    found = _resolve_review(opened, context, target, "dismiss")
    object_id, review = _review(opened, found, now)
    if review["state"] == "DISMISSED":
        return _already(opened, found, object_id, review, flags["plan"], now)
    if review["state"] not in DISMISSABLE:
        fail("timvisher_gh_review_not_dismissable", f"{found.url} is a {review['state']} review, and GitHub dismisses "
             "only APPROVED and CHANGES_REQUESTED ones.")
    spec = f"{found.owner}/{found.repo}"
    if not _write_access(spec):
        fail("timvisher_gh_review_dismiss_no_write", f"Dismissing {found.url} needs write access to {spec}, and you "
             "don't have it.", reason="GitHub lets only collaborators with write access dismiss reviews; nothing was "
             "dismissed.", suggestions=[f"Ask a maintainer of {spec} to dismiss it"])
    author = review["user"]["login"]
    theirs = author.lower() != fetch.api(spec, "user")["login"].lower()
    if flags["force"] and theirs:
        fail("timvisher_gh_dismiss_not_yours", f"{found.url} is {author}'s review, so --force won't dismiss it.",
             status=USAGE, suggestions=["Rerun without --force to confirm dismissing someone else's review"])
    if flags["plan"]:
        print(f"~ review  {found.url}  dismiss {author}'s {review['state']} review")
        return 0
    if not flags["force"] and not nouns.confirm(f"Dismiss {author}'s {review['state']} review {found.url}? "
                                                "It can't be undone."):
        aictl.info(code="timvisher_gh_dismiss_skipped", message=f"Left {found.url} {review['state']}.")
        return 0
    # place, not promote: promote's authored row would have backfill relink
    # the message to review.md, the review's own body.
    with opened.write() as db:
        store.place(source, _message_file(db, object_id))
        pr.set_source_state(db, object_id, {"state": "DISMISSED"}, now)
        opened.touch(object_id)
    return _apply(opened, found, object_id, flags, now)


def push(opened, context, positionals, flags, now):
    if len(positionals) != 1:
        usage("review push needs one <target>")
    found = _resolve_review(opened, context, positionals[0], "push")
    object_id, review = _review(opened, found, now)
    if pr.source_state(opened.db, object_id).get("state") is None:
        aictl.info(code="timvisher_gh_nothing_to_do", message=f"{found.url} has no wanted state to push.",
                   suggestions=[f"Dismiss it with 'timvisher_gh review dismiss {found.url} <message-file>'"])
        return 0
    if review["state"] == "DISMISSED":
        return _already(opened, found, object_id, review, flags["plan"], now)
    return _apply(opened, found, object_id, flags, now)


def run(context, args):
    verb = args[0] if args else None
    if verb in ("-h", "--help"):
        sys.stdout.write(USAGE_TEXT)
        return 0
    if verb not in ("delete", "dismiss", "push"):
        usage(f"Unknown review command: '{verb or ''}'", "Commands: review delete, dismiss, push, info")
    parsed = _parse(args[1:])
    if parsed is None:
        return 0
    positionals, flags = parsed
    opened = state.open_state()
    now = nouns.now()
    try:
        store.exporting(opened, lambda object_id: record.record(opened.db, object_id), nouns.now)
        return {"delete": delete, "dismiss": dismiss, "push": push}[verb](opened, context, positionals, flags, now)
    except fetch.NotFound as missing:
        fail("timvisher_gh_not_found", f"GitHub has no such review or PR ({missing}).",
             suggestions=["Check the URL, and that your gh account can see the repository"])
    finally:
        opened.close()
