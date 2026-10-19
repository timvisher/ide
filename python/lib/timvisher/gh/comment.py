import json
import pathlib
import sys

from timvisher import aictl
from timvisher.gh import adopt, fetch, nouns, pr, record, state, store, sync, targets
from timvisher.gh.errors import ERROR, USAGE, Exit, fail, usage

USAGE_TEXT = """\
Usage: timvisher_gh [-C <path>] comment [<target>] <file> [--reaction R]...
       timvisher_gh [-C <path>] comment fetch|pull|push [<target>] [<file>]
       timvisher_gh [-C <path>] comment reply <target> <file> [--reaction R]...
       timvisher_gh [-C <path>] comment edit <file-or-target>
       timvisher_gh [-C <path>] comment react [--delete] <target> <reaction>...
       timvisher_gh [-C <path>] comment info <target> [<component>]
       timvisher_gh [-C <path>] comment delete [--force] <target>

  comment [<target>] <file>  sync <file>, creating the comment on its first push.
                             A PR target (or none: the worktree's PR) makes a
                             top-level comment; a review comment or thread target
                             makes a reply in that thread. A top-level comment
                             target is an error. --reaction R reacts to the target.
  reply <target> <file>      as the bare form, but the target must be a review
                             comment or thread; replying to a reply posts at the root
  edit <file-or-target>      update only: an error if the comment doesn't exist
  react [--delete] <target> <reaction>...
                             add or remove your reactions; a no-op where GitHub
                             already matches, and removing one you haven't made is
                             skipped
  delete [--force] <target>  delete the comment on GitHub, then archive our copy;
                             prompts unless --force, and --force refuses someone
                             else's comment
  info <target> [<component>]  the record (see 'comment info --help')

Reactions: +1 -1 laugh confused heart hooray rocket eyes, the emoji
👍 👎 😄 😕 ❤️ 🎉 🚀 👀 (no skin tones), or a GraphQL ReactionContent name
(THUMBS_UP, THUMBS_DOWN, LAUGH, ...).

Options for the syncing forms: --plan, --ours, --theirs, --merge.
"""

REACTIONS = {
    "+1": "+1", "thumbs_up": "+1", "👍": "+1",
    "-1": "-1", "thumbs_down": "-1", "👎": "-1",
    "laugh": "laugh", "😄": "laugh",
    "confused": "confused", "😕": "confused",
    "heart": "heart", "❤️": "heart", "❤": "heart",
    "hooray": "hooray", "🎉": "hooray",
    "rocket": "rocket", "🚀": "rocket",
    "eyes": "eyes", "👀": "eyes",
}


def reaction(raw):
    name = REACTIONS.get(raw.strip().lower())
    if name is None:
        usage(f"'{raw}' isn't a reaction.",
              "Use one of +1 -1 laugh confused heart hooray rocket eyes, the matching emoji "
              "👍 👎 😄 😕 ❤️ 🎉 🚀 👀 without skin tones, or a GraphQL ReactionContent name")
    return name


def _endpoint(target):
    spec = f"{target.owner}/{target.repo}"
    table = "issues" if target.kind == "comment" else "pulls"
    return spec, f"repos/{spec}/{table}/comments/{target.comment_id}"


def _comment_target(db, object_id):
    url = db.execute("SELECT url FROM objects WHERE id = ?", (object_id,)).fetchone()[0]
    return targets.parse_url(url, "comment")


class CommentAdapter:
    managed = ("body",)

    def __init__(self, opened, now):
        self.state = opened
        self.now = now

    def fetch(self, item):
        spec, endpoint = _endpoint(_comment_target(self.state.db, item.object_id))
        found = fetch.api(spec, endpoint)
        raw = self.state.db.execute("SELECT payload FROM raw WHERE object_id = ?", (item.object_id,)).fetchone()
        stored = json.loads(raw[0]) if raw else {}
        payload = {**stored, "root": found} if "root" in stored else found
        self.state.db.execute("INSERT INTO raw VALUES (?, ?, ?) ON CONFLICT (object_id) DO UPDATE SET "
                              "payload = excluded.payload, fetched_at = excluded.fetched_at",
                              (item.object_id, json.dumps(payload), self.now))
        return {"body": found["body"]}

    def read_source(self, item):
        store.backfill(self.state.db, item.object_id)
        return {"body": sync.normalize(store.store_file(self.state.db, item.object_id).read_text(encoding="utf-8"))}

    def write_source(self, item, values):
        store._write_atomic(store.store_file(self.state.db, item.object_id), store.source_text("comment", values))

    def push(self, item, values):
        spec, endpoint = _endpoint(_comment_target(self.state.db, item.object_id))
        fetch.api(spec, "-X", "PATCH", endpoint, "-f", f"body={values['body']}")


def _mine(db, object_id, viewer):
    payload = json.loads(db.execute("SELECT payload FROM raw WHERE object_id = ?", (object_id,)).fetchone()[0])
    author = (payload.get("root") or payload).get("user", {}).get("login") or ""
    return author.lower() == viewer.lower()


def _yours(spec, endpoint, viewer):
    return {r["content"]: r["id"] for r in fetch.api(spec, "--paginate", f"{endpoint}/reactions")
            if r["user"]["login"].lower() == viewer.lower()}


def _react(opened, target, names, delete, viewer, now):
    spec, endpoint = _endpoint(target)
    have = _yours(spec, endpoint, viewer)
    failed = []
    for name in names:
        try:
            if delete and name in have:
                fetch.api(spec, "-X", "DELETE", f"{endpoint}/reactions/{have.pop(name)}")
            elif not delete and name not in have:
                have[name] = fetch.api(spec, f"{endpoint}/reactions", "-f", f"content={name}")["id"]
        except Exit:
            failed.append(name)
    observed = sorted(_yours(spec, endpoint, viewer))
    row = opened.db.execute("SELECT id FROM objects WHERE url = ? COLLATE NOCASE", (target.url,)).fetchone()
    if row:
        with opened.write() as db:
            store.set_remote(db, row[0], "reactions", observed, now)
            opened.touch(row[0])
    missing = [n for n in names if (n in observed) == delete]
    if failed or missing:
        aictl.error(code="timvisher_gh_reaction_failed",
                    message=f"Reactions on {target.url} didn't converge: {', '.join(failed or missing)}.",
                    suggestions=["Rerun the same command; reactions already in place are skipped"])
        return ERROR
    return 0


def _object(opened, target, now):
    db = opened.db
    row = db.execute("SELECT id FROM objects WHERE url = ? COLLATE NOCASE", (target.url,)).fetchone()
    if row is None:
        with opened.write():
            fetch.Fetcher(opened, now).pr(target.owner, target.repo, target.number, only_new=True)
        row = db.execute("SELECT id FROM objects WHERE url = ? COLLATE NOCASE", (target.url,)).fetchone()
    return row and row[0]


def _lookup(target):
    if target.kind in ("pr", "issue"):
        return pr._lookup(target)
    spec, endpoint = _endpoint(target)
    found = fetch.api(spec, endpoint)
    facts = {"id": found["node_id"], "database_id": found["id"], "kind": "issue_comment" if target.kind == "comment"
             else "review_comment", "author": found["user"]["login"], "created_at": found["created_at"],
             "body": found["body"]}
    if target.kind == "comment":
        return facts
    root_id = found.get("in_reply_to_id") or found["id"]
    threads = fetch.api(spec, "graphql", "-f", f"query={fetch.REVIEW_THREADS}", "-f", f"owner={target.owner}",
                        "-f", f"repo={target.repo}", "-F", f"number={target.number}")
    node = next(n for n in threads["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"]
                if n["comments"]["nodes"] and n["comments"]["nodes"][0]["databaseId"] == root_id)
    facts.update(thread_id=node["id"], in_reply_to=found.get("in_reply_to_id"), path=found.get("path"),
                 line=found.get("line"))
    if found.get("in_reply_to_id"):
        root = fetch.api(spec, f"repos/{spec}/pulls/comments/{root_id}")
        facts["thread"] = {"thread_id": node["id"], "id": root["node_id"], "database_id": root["id"],
                           "url": root["html_url"], "author": root["user"]["login"],
                           "created_at": root["created_at"], "path": root.get("path"), "line": root.get("line"),
                           "posted": {}}
    return facts


def _root(target):
    spec, endpoint = _endpoint(target)
    found = fetch.api(spec, endpoint)
    return found.get("in_reply_to_id") or found["id"]


def _create(opened, where, source, now):
    values = {"body": pathlib.Path(source).read_text(encoding="utf-8").rstrip("\n")}
    spec = f"{where.owner}/{where.repo}"
    if where.kind == "pr":
        created = fetch.api(spec, f"repos/{spec}/issues/{where.number}/comments", "-f", f"body={values['body']}")
    else:
        created = fetch.api(spec, f"repos/{spec}/pulls/{where.number}/comments/{_root(where)}/replies",
                            "-f", f"body={values['body']}")
    with opened.write() as db:
        fetch.Fetcher(opened, now).pr(where.owner, where.repo, where.number, only_new=True)
        object_id = db.execute("SELECT id FROM objects WHERE url = ? COLLATE NOCASE",
                               (created["html_url"],)).fetchone()[0]
        store.set_base(db, object_id, "body", values["body"], now)
        store.promote(db, object_id, source)
        opened.touch(object_id)
    return created["html_url"]


def _split(args, flags):
    positionals, rest = [], list(args)
    while rest:
        arg = rest.pop(0)
        match arg:
            case "-h" | "--help":
                sys.stdout.write(USAGE_TEXT)
                return None
            case "--reaction":
                if not rest:
                    usage("--reaction requires a value")
                flags["reactions"].append(reaction(rest.pop(0)))
            case _ if arg.startswith("--reaction="):
                flags["reactions"].append(reaction(arg.removeprefix("--reaction=")))
            case "--plan":
                flags["plan"] = True
            case "--ours" | "--theirs" | "--merge":
                if flags["resolution"]:
                    usage("--ours, --theirs and --merge are mutually exclusive")
                flags["resolution"] = arg[2:]
            case "--delete":
                flags["delete"] = True
            case "--force" | "-f":
                flags["force"] = True
            case "--":
                positionals.extend(rest)
                break
            case _ if arg.startswith("-") and arg not in REACTIONS:
                usage(f"comment: unknown option '{arg}'", "See 'timvisher_gh comment --help'")
            case _:
                positionals.append(arg)
    return positionals


def _sync(opened, verb, object_id, flags, viewer, now, rerun):
    url = opened.db.execute("SELECT url FROM objects WHERE id = ?", (object_id,)).fetchone()[0]
    item = sync.Item(object_id, "comment", url, CommentAdapter(opened, now), mine=_mine(opened.db, object_id, viewer))
    return sync.Engine(opened, verb, now=now, rerun=rerun, resolution=flags["resolution"], plan_only=flags["plan"],
                       ask=sync.prompt if sync.interactive() else None).run([item]), url


def _thread_of(db, object_id):
    row = db.execute("SELECT o.kind, p.id, p.kind FROM objects o LEFT JOIN objects p ON p.id = o.parent_id "
                     "WHERE o.id = ?", (object_id,)).fetchone()
    if row is None:
        return None
    kind, parent, parent_kind = row
    return object_id if kind == "thread" else (parent if parent_kind == "thread" else None)


def _delete(opened, target, force, viewer, now):
    spec, endpoint = _endpoint(target)
    found = fetch.api(spec, endpoint)
    theirs = found["user"]["login"].lower() != viewer.lower()
    if force and theirs:
        fail("timvisher_gh_delete_not_yours",
             f"{target.url} is {found['user']['login']}'s comment, so --force won't delete it.",
             status=USAGE, suggestions=["Rerun without --force to confirm deleting someone else's comment"])
    if not force:
        sys.stderr.write(f"Delete {target.url}{' (by ' + found['user']['login'] + ')' if theirs else ''}? [y/N] ")
        sys.stderr.flush()
        if sys.stdin.readline().strip().lower() not in ("y", "yes"):
            aictl.info(code="timvisher_gh_delete_skipped", message=f"Kept {target.url}.")
            return 0
    fetch.api(spec, "-X", "DELETE", endpoint)
    try:
        fetch.api(spec, endpoint)
    except fetch.NotFound:
        row = opened.db.execute("SELECT id FROM objects WHERE url = ? COLLATE NOCASE", (target.url,)).fetchone()
        if row:
            with opened.write() as db:
                store.archive(db, row[0], now)
                opened.touch(row[0])
        return 0
    fail("timvisher_gh_delete_unconfirmed", f"GitHub still shows {target.url} after deleting it; our copy is kept.",
         suggestions=["Rerun the delete"])


def run(context, args):
    verb = "sync"
    rest = list(args)
    if rest and rest[0] in ("fetch", "pull", "push", "reply", "edit", "react", "delete"):
        verb = rest.pop(0)
    flags = {"reactions": [], "plan": False, "resolution": None, "delete": False, "force": False}
    positionals = _split(rest, flags)
    if positionals is None:
        return 0
    rerun = "timvisher_gh comment" + ("" if verb == "sync" else f" {verb}")
    opened = state.open_state()
    now = nouns.now()
    try:
        store.exporting(opened, lambda object_id: record.record(opened.db, object_id), nouns.now)
        if verb == "react":
            if len(positionals) < 2:
                usage("comment react needs a <target> and at least one <reaction>")
            found = targets.resolve("comment", positionals[0], context=context, db=opened.db)
            if found.kind not in ("comment", "review_comment", "thread"):
                usage(f"'{found.url}' names a {found.kind}, so comment react can't use it.")
            names = [reaction(name) for name in positionals[1:]]
            return _react(opened, found, names, flags["delete"], fetch.api(f"{found.owner}/{found.repo}", "user")["login"], now)
        if verb == "delete":
            if len(positionals) != 1:
                usage("comment delete needs one <target>")
            found = targets.resolve("comment", positionals[0], context=context, db=opened.db)
            if found.kind not in ("comment", "review_comment", "thread"):
                usage(f"'{found.url}' names a {found.kind}, so comment delete can't use it.")
            return _delete(opened, found, flags["force"], fetch.api(f"{found.owner}/{found.repo}", "user")["login"],
                           now)

        if verb == "edit":
            if len(positionals) != 1:
                usage("comment edit needs one <file-or-target>")
            target_arg, file_arg = None, positionals[0]
        elif verb == "reply":
            if len(positionals) != 2:
                usage("comment reply needs a <target> and a <file>")
            target_arg, file_arg = positionals
        elif len(positionals) == 2:
            target_arg, file_arg = positionals
        elif len(positionals) == 1:
            target_arg, file_arg = None, positionals[0]
        else:
            usage(f"comment {'' if verb == 'sync' else verb + ' '}needs a <file>", "See 'timvisher_gh comment --help'")

        if context is not None:
            adopt.adopt_root(opened, context.toplevel, pr._lookup, now)
            adopt.adopt_directory(opened, context.toplevel, "pr", pr._lookup, now)
        source = pathlib.Path(file_arg)
        if source.is_file() and not source.is_symlink() and any(
                source.with_name(source.name + suffix).is_file() for suffix in (".url", ".json")):
            adopt.adopt_comment(opened, source, _lookup, now)
        tracked = targets.resolve("comment", file_arg, context=context, db=opened.db, creating=True)
        if target_arg is not None:
            where = targets.resolve("comment", target_arg, context=context, db=opened.db)
        elif tracked.kind == "source" and verb != "edit":
            where = targets.resolve("comment", None, context=context, db=opened.db)
        else:
            where = None
        if where is not None and verb == "reply" and where.kind not in ("review_comment", "thread"):
            usage(f"'{where.url}' isn't a review comment or thread, so comment reply can't reply to it.",
                  "Use 'timvisher_gh comment <pr> <file>' for a top-level comment")
        if where is not None and where.kind == "comment":
            usage(f"'{where.url}' is a top-level comment, which has no thread to reply in.",
                  "Target the PR for a new top-level comment, or a review comment to reply in its thread")
        if flags["reactions"] and (where is None or where.kind == "pr"):
            usage("--reaction reacts to the target comment, so it needs a comment target")

        viewer = fetch.api(f"{(where or tracked).owner}/{(where or tracked).repo}", "user")["login"]
        if tracked.kind == "source":
            if verb in ("fetch", "pull"):
                aictl.info(code="timvisher_gh_nothing_to_do",
                           message=f"{file_arg} isn't posted yet, so {verb} has nothing to do.")
                return 0
            if verb == "edit":
                fail("timvisher_gh_comment_missing", f"{file_arg} isn't a posted comment, so there's nothing to edit.",
                     suggestions=[f"Post it with 'timvisher_gh comment <target> {file_arg}'"])
            if flags["plan"]:
                print(f"+ comment (new on {where.url})  post {file_arg}")
                return 0
            url = _create(opened, where, file_arg, now)
            print(url)
            rc = 0
        else:
            object_id = tracked.object_id or _object(opened, tracked, now)
            if opened.db.execute("SELECT 1 FROM raw WHERE object_id = ?", (object_id,)).fetchone() is None:
                with opened.write():
                    CommentAdapter(opened, now).fetch(sync.Item(object_id, "comment", tracked.url, None))
            if where is not None and where.kind in ("review_comment", "thread"):
                wanted = _object(opened, where, now)
                if _thread_of(opened.db, object_id) != _thread_of(opened.db, wanted):
                    usage(f"{file_arg} is already posted as {tracked.url}, not in {where.url}'s thread.",
                          "Use a new file for a reply in another thread")
            if not _mine(opened.db, object_id, viewer) and verb in ("push", "edit"):
                aictl.notice(code="timvisher_gh_read_only",
                             message=f"{tracked.url} is someone else's comment; only pull and fetch apply to it.")
            engine_verb = {"edit": "edit", "reply": "sync"}.get(verb, verb)
            rc, url = _sync(opened, engine_verb, object_id, flags, viewer, now, rerun)
            if rc == 0 and not flags["plan"]:
                print(url)
        if rc == 0 and flags["reactions"] and not flags["plan"]:
            rc = _react(opened, where, flags["reactions"], False, viewer, now)
        return rc
    except fetch.NotFound as missing:
        fail("timvisher_gh_not_found", f"GitHub has no such comment or PR ({missing}).",
             suggestions=["Check the URL, and that your gh account can see the repository"])
    finally:
        opened.close()
    return ERROR
