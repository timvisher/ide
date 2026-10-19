import datetime
import json
import os
import subprocess
import sys

from timvisher.gh import fetch, record, state, store, targets
from timvisher.gh.errors import ERROR, fail, usage

NOUNS = ("pr", "issue", "comment", "thread")

ACCEPTS = {
    "pr": ("pr", "comment", "review_comment", "thread"),
    "issue": ("issue",),
    "comment": ("comment", "review_comment"),
    "thread": ("thread",),
}


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def info_help(noun):
    kinds = {"pr": ("pr",), "issue": ("issue",), "comment": ("comment",), "thread": ("thread",)}[noun]
    lines = [f"Usage: timvisher_gh [-C <path>] {noun} info [--schema-version <N>] [<target>] [<component>]", "",
             f"Print the {noun}'s record as JSON, or one <component> of it: a jq path, with",
             "jq -r semantics (scalars print bare, anything else as JSON). It reads the",
             "state and never touches your files; an object the state doesn't know yet is",
             "fetched first. Run fetch or pull to refresh a known one.", "",
             f"Fields (schema_version {record.SCHEMA_VERSION}):"]
    for group in ("common", *kinds):
        for name, meaning in record.FIELDS[group]:
            lines.append(f"  {name:<16} {meaning}")
    if noun == "pr":
        lines.append("  (a review's record has: " + ", ".join(n for n, _ in record.FIELDS["review"]) + ")")
    lines += ["", "--schema-version <N> exits 1 unless schema_version is <N>.", "", record.COMPATIBILITY, ""]
    return "\n".join(lines)


def _parse_info(noun, args):
    target = component = pin = None
    rest = list(args)
    while rest:
        arg = rest.pop(0)
        if arg in ("-h", "--help"):
            sys.stdout.write(info_help(noun))
            return None
        if arg == "--schema-version":
            if not rest:
                usage("--schema-version requires <N>")
            pin = rest.pop(0)
        elif arg.startswith(".") and not os.path.lexists(arg) and component is None:
            component = arg
        elif target is None and component is None:
            target = arg
        else:
            usage(f"{noun} info: unexpected argument '{arg}'", f"Usage: timvisher_gh {noun} info [<target>] [<component>]")
    return target, component, pin


OWN_KIND = {"pr": "pr", "issue": "issue", "thread": "thread"}


def _object_id(db, found, noun):
    object_id = found.object_id
    if object_id is None:
        url = found.pr_url if noun == "pr" else found.url
        row = db.execute("SELECT id FROM objects WHERE url = ? COLLATE NOCASE", (url,)).fetchone()
        object_id = row and row[0]
    while object_id is not None and noun in OWN_KIND:
        kind, parent = db.execute("SELECT kind, parent_id FROM objects WHERE id = ?", (object_id,)).fetchone()
        if kind == OWN_KIND[noun] or parent is None:
            break
        object_id = parent
    return object_id


def _remember_context(opened, context, found, object_id):
    if found.via != "context" or found.object_id is not None or context is None:
        return
    branch = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=context.toplevel,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout.strip()
    owner, repo = context.spec.split("/")
    with opened.write() as db:
        db.execute("INSERT INTO context VALUES (?, ?, ?, ?, ?) ON CONFLICT (worktree) DO UPDATE SET "
                   "owner = excluded.owner, repo = excluded.repo, branch = excluded.branch, pr_id = excluded.pr_id",
                   (context.toplevel, owner, repo, branch, object_id))


def _fetch(opened, found, noun):
    fetcher = fetch.Fetcher(opened, now())
    try:
        with opened.write():
            if found.kind == "issue":
                fetcher.issue(found.owner, found.repo, found.number, only_new=True)
            else:
                fetcher.pr(found.owner, found.repo, found.number, only_new=True)
    except fetch.NotFound:
        fail("timvisher_gh_not_found", f"GitHub has no {noun} at {found.url}.",
             suggestions=["Check the URL, and that your gh account can see the repository"])


def info(noun, context, args):
    parsed = _parse_info(noun, args)
    if parsed is None:
        return 0
    target, component, pin = parsed
    if pin is not None and pin != str(record.SCHEMA_VERSION):
        fail("timvisher_gh_schema_version_mismatch",
             f"timvisher_gh's records are schema_version {record.SCHEMA_VERSION}, not {pin}.",
             reason="info --schema-version pins the record contract; this tool serves only its current version.",
             suggestions=[f"Update the caller for schema_version {record.SCHEMA_VERSION} and pass "
                          f"--schema-version {record.SCHEMA_VERSION}",
                          f"See 'timvisher_gh {noun} info --help' for the fields and what changed between versions"])
    opened = state.open_state()
    try:
        store.exporting(opened, lambda object_id: record.record(opened.db, object_id), now)
        found = targets.resolve(noun, target, context=context, db=opened.db)
        if found.kind not in ACCEPTS[noun]:
            usage(f"'{found.url}' names a {found.kind}, so {noun} info can't use it.", f"Use 'timvisher_gh {found.kind} info'"
                  if found.kind in NOUNS else f"Pass a {noun} URL")
        object_id = _object_id(opened.db, found, noun)
        if object_id is None:
            _fetch(opened, found, noun)
            object_id = _object_id(opened.db, found, noun)
        if object_id is None:
            fail("timvisher_gh_not_found", f"GitHub has no {noun} at {found.url}.",
                 suggestions=[f"Check the URL; 'timvisher_gh pr fetch {found.pr_url}' lists the PR's conversation"])
        _remember_context(opened, context, found, object_id)
        kind = opened.db.execute("SELECT kind FROM objects WHERE id = ?", (object_id,)).fetchone()[0]
        if noun == "comment" and kind == "thread":
            result = record.as_comment(opened.db, object_id)
        else:
            result = record.record(opened.db, object_id)
    finally:
        opened.close()
    text = json.dumps(result, indent=2, ensure_ascii=False)
    if component is None:
        print(text)
        return 0
    done = subprocess.run(["jq", "-r", component], input=text, stdout=subprocess.PIPE, text=True)
    sys.stdout.write(done.stdout)
    return 0 if done.returncode == 0 else ERROR


def run(noun, context, args):
    if args[:1] == ["info"]:
        return info(noun, context, args[1:])
    usage(f"Unknown {noun} command: '{args[0] if args else ''}'", f"Commands: {noun} info")
