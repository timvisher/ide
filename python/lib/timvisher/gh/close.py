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
    "issue": """\
Usage: timvisher_gh [-C <path>] issue close [<target>] [--reason completed|not_planned] [--plan]
       timvisher_gh [-C <path>] issue reopen [<target>] [--plan]

Close or reopen the issue: the worktree's tracked issue.md, with no
<target>. An issue already in that state is reported and left alone;
closing a closed issue with a different --reason changes only its
reason. The stored record's state is refreshed either way. --plan shows
what it would do and changes nothing.
""",
}

REASONS = ("completed", "not_planned")

WANTED = {"close": "closed", "reopen": "open"}


def parse(noun, verb, args):
    target, plan, reason = None, False, None
    rest = list(args)
    while rest:
        arg = rest.pop(0)
        if arg in ("-h", "--help"):
            sys.stdout.write(USAGE[noun])
            return None
        if arg == "--plan":
            plan = True
        elif (arg == "--reason" or arg.startswith("--reason=")) and noun == "issue" and verb == "close":
            if arg == "--reason" and not rest:
                usage("--reason requires completed or not_planned")
            reason = rest.pop(0) if arg == "--reason" else arg.removeprefix("--reason=")
            if reason not in REASONS:
                usage(f"--reason must be completed or not_planned, not '{reason}'")
        elif arg.startswith("-") or target is not None:
            usage(f"{noun} {verb}: unexpected argument '{arg}'", f"See 'timvisher_gh {noun} {verb} --help'")
        else:
            target = arg
    return target, plan, reason


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
    raw = json.loads(opened.db.execute("SELECT payload FROM raw WHERE object_id = ?", (object_id,)).fetchone()[0])
    url = opened.db.execute("SELECT url FROM objects WHERE id = ?", (object_id,)).fetchone()[0]
    return object_id, current, raw.get("state_reason"), url


def _line(marker, noun, url, what):
    return f"{marker} {noun:<7} {url}  {what}"


def _describe(current, current_reason):
    return f"{current} as {current_reason}" if current == "closed" and current_reason else current


def change(opened, context, noun, verb, target, plan, reason=None):
    wanted = WANTED[verb]
    found = _resolve(opened, context, noun, verb, target)
    now = nouns.now()
    object_id, current, current_reason, url = _refresh(opened, noun, found, now)
    if current == "merged" and verb == "reopen":
        fail("timvisher_gh_pr_merged", f"{url} is merged, and GitHub can't reopen a merged PR.")
    done = (current == wanted and (reason is None or reason == current_reason)) or (
        current == "merged" and verb == "close")
    if current != wanted:
        what = f"{verb} as {reason}" if reason else verb
    else:
        what = f"change the reason from {current_reason or 'none'} to {reason}"
    if plan:
        print(_line(" ", noun, url, f"unchanged: already {_describe(current, current_reason)}") if done
              else _line("~", noun, url, what))
        return 0
    if done:
        aictl.info(code=f"timvisher_gh_already_{wanted}",
                   message=f"{url} is already {_describe(current, current_reason)}.")
        print(url)
        return 0
    owner, repo, number = opened.db.execute("SELECT owner, repo, number FROM objects WHERE id = ?",
                                            (object_id,)).fetchone()
    spec = f"{owner}/{repo}"
    fields = ["-f", f"state={wanted}"] + (["-f", f"state_reason={reason}"] if reason is not None else [])
    fetch.api(spec, "-X", "PATCH", f"repos/{spec}/{'pulls' if noun == 'pr' else 'issues'}/{number}", *fields)
    _, current, current_reason, _ = _refresh(opened, noun, found, now)
    if current != wanted or (reason is not None and current_reason != reason):
        aictl.error(code=f"timvisher_gh_{verb}_failed", message=f"{url} is still "
                    f"{_describe(current, current_reason)} after asking GitHub to {what}.",
                    suggestions=["Rerun the same command"])
        return ERROR
    aictl.info(code=f"timvisher_gh_{'closed' if verb == 'close' else 'reopened'}",
               message=f"{'Closed' if verb == 'close' else 'Reopened'} {url}"
                       f"{' as ' + current_reason if verb == 'close' and current_reason else ''}.")
    print(url)
    return 0


def run(noun, verb, context, args):
    parsed = parse(noun, verb, args)
    if parsed is None:
        return 0
    target, plan, reason = parsed
    opened = state.open_state()
    try:
        store.exporting(opened, lambda object_id: record.record(opened.db, object_id), nouns.now)
        return change(opened, context, noun, verb, target, plan, reason)
    except fetch.NotFound as missing:
        fail("timvisher_gh_not_found", f"GitHub has no such {noun} ({missing}).",
             suggestions=["Check the URL, and that your gh account can see the repository"])
    finally:
        opened.close()
