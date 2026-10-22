import json
import sys

from timvisher import aictl
from timvisher.gh import fetch, nouns, record, state, store, targets
from timvisher.gh.errors import ERROR, fail, usage

USAGE = {
    "pr": """\
Usage: timvisher_gh [-C <path>] pr close|reopen [<target>] [--plan]

Close or reopen the PR: the worktree's, with no <target>. A PR already
in that state is reported and left alone, and a merged PR can't be
reopened. The stored record's state is refreshed either way. --plan
shows what it would do and changes nothing.
""",
}

WANTED = {"close": "closed", "reopen": "open"}


def parse(noun, verb, args):
    target, plan = None, False
    for arg in args:
        if arg in ("-h", "--help"):
            sys.stdout.write(USAGE[noun])
            return None
        if arg == "--plan":
            plan = True
        elif arg.startswith("-") or target is not None:
            usage(f"{noun} {verb}: unexpected argument '{arg}'", f"See 'timvisher_gh {noun} {verb} --help'")
        else:
            target = arg
    return target, plan


def _resolve(opened, context, noun, verb, target):
    found = targets.resolve(noun, target, context=context, db=opened.db, creating=True)
    if found.kind == "source":
        fail(f"timvisher_gh_{noun}_missing", f"There's no {noun} for {found.source} to {verb}.",
             suggestions=[f"Create it with 'timvisher_gh {noun} push'"])
    if found.kind not in nouns.ACCEPTS[noun]:
        usage(f"'{found.url}' names a {found.kind}, so {noun} {verb} can't use it.")
    return found


def _refresh(opened, noun, found, now):
    fetcher = fetch.Fetcher(opened, now)
    with opened.write():
        if noun == "pr":
            object_id = fetcher.pr(found.owner, found.repo, found.number, conversation=False)
        else:
            object_id = fetcher.issue(found.owner, found.repo, found.number)
    current = json.loads(opened.db.execute("SELECT remote FROM fields WHERE object_id = ? AND name = 'state'",
                                           (object_id,)).fetchone()[0])
    url = opened.db.execute("SELECT url FROM objects WHERE id = ?", (object_id,)).fetchone()[0]
    return object_id, current, url


def _line(marker, noun, url, what):
    return f"{marker} {noun:<7} {url}  {what}"


def change(opened, context, noun, verb, target, plan):
    wanted = WANTED[verb]
    found = _resolve(opened, context, noun, verb, target)
    now = nouns.now()
    object_id, current, url = _refresh(opened, noun, found, now)
    if current == "merged" and verb == "reopen":
        fail("timvisher_gh_pr_merged", f"{url} is merged, and GitHub can't reopen a merged PR.")
    done = current == wanted or (current == "merged" and verb == "close")
    if plan:
        print(_line(" ", noun, url, f"unchanged: already {current}") if done else _line("~", noun, url, verb))
        return 0
    if done:
        aictl.info(code=f"timvisher_gh_already_{wanted}", message=f"{url} is already {current}.")
        print(url)
        return 0
    spec = f"{found.owner}/{found.repo}"
    number = opened.db.execute("SELECT number FROM objects WHERE id = ?", (object_id,)).fetchone()[0]
    fetch.api(spec, "-X", "PATCH", f"repos/{spec}/{'pulls' if noun == 'pr' else 'issues'}/{number}",
              "-f", f"state={wanted}")
    _, current, _ = _refresh(opened, noun, found, now)
    if current != wanted:
        aictl.error(code=f"timvisher_gh_{verb}_failed", message=f"{url} is still {current} after asking GitHub to "
                    f"{verb} it.", suggestions=["Rerun the same command"])
        return ERROR
    aictl.info(code=f"timvisher_gh_{'closed' if verb == 'close' else 'reopened'}",
               message=f"{'Closed' if verb == 'close' else 'Reopened'} {url}.")
    print(url)
    return 0


def run(noun, verb, context, args):
    parsed = parse(noun, verb, args)
    if parsed is None:
        return 0
    target, plan = parsed
    opened = state.open_state()
    try:
        store.exporting(opened, lambda object_id: record.record(opened.db, object_id), nouns.now)
        return change(opened, context, noun, verb, target, plan)
    except fetch.NotFound as missing:
        fail("timvisher_gh_not_found", f"GitHub has no such {noun} ({missing}).",
             suggestions=["Check the URL, and that your gh account can see the repository"])
    finally:
        opened.close()
