import json
import pathlib
import sys

from timvisher import aictl, browser
from timvisher.gh import adopt, fetch, nouns, pr, record, state, store, sync, targets
from timvisher.gh.errors import ERROR, fail, usage

USAGE = """\
Usage: timvisher_gh [-C <path>] issue [fetch|pull|push|edit] [<target>] [options]
       timvisher_gh [-C <path>] issue info [<target>] [<component>]

  issue [<target>]   sync the title and body: pull, then push
  issue fetch        update the state; writes no files
  issue pull         fetch, then write GitHub's changes into the source
  issue push         fetch, then push the title and body, creating the issue
                     from the source if there is none
  issue edit         as push, but an error if the issue doesn't exist

Options: --plan, --ours, --theirs, --merge, --open

The source is <toplevel>/issue.md: the title on line 1, the body from line 3.
"""


class IssueAdapter:
    managed = ("title", "body")

    def __init__(self, opened, fetcher):
        self.state = opened
        self.fetcher = fetcher

    def _row(self, item):
        return self.state.db.execute("SELECT owner, repo, number FROM objects WHERE id = ?",
                                     (item.object_id,)).fetchone()

    def fetch(self, item):
        owner, repo, number = self._row(item)
        self.fetcher.issue(owner, repo, number)
        raw = json.loads(self.state.db.execute("SELECT payload FROM raw WHERE object_id = ?",
                                               (item.object_id,)).fetchone()[0])
        return {"title": raw["title"], "body": raw.get("body") or ""}

    def read_source(self, item):
        store.backfill(self.state.db, item.object_id)
        return pr.parse_source(store.store_file(self.state.db, item.object_id).read_text(encoding="utf-8"))

    def write_source(self, item, values):
        store._write_atomic(store.store_file(self.state.db, item.object_id), store.source_text("issue", values))

    def push(self, item, values):
        owner, repo, number = self._row(item)
        spec = f"{owner}/{repo}"
        fields = [arg for name in ("title", "body") if name in values for arg in ("-f", f"{name}={values[name]}")]
        fetch.api(spec, "-X", "PATCH", f"repos/{spec}/issues/{number}", *fields)


def parse(args):
    verb, target, flags = None, None, {"resolution": None, "plan": False, "open": False}
    rest = list(args)
    if rest and rest[0] in pr.VERBS:
        verb = rest.pop(0)
    while rest:
        arg = rest.pop(0)
        match arg:
            case "-h" | "--help":
                sys.stdout.write(USAGE)
                return None
            case "--plan":
                flags["plan"] = True
            case "--ours" | "--theirs" | "--merge":
                if flags["resolution"]:
                    usage("--ours, --theirs and --merge are mutually exclusive")
                flags["resolution"] = arg[2:]
            case "--open":
                flags["open"] = True
            case "--no-open":
                flags["open"] = False
            case _ if arg.startswith("-"):
                usage(f"issue: unknown option '{arg}'", "See 'timvisher_gh issue --help'")
            case _ if target is None:
                target = arg
            case _:
                usage(f"issue: unexpected argument '{arg}'", "See 'timvisher_gh issue --help'")
    return verb or "sync", target, flags


def _create(opened, context, source, flags):
    values = pr.parse_source(pathlib.Path(source).read_text(encoding="utf-8"))
    spec = context.spec
    if flags["plan"]:
        print(f"+ issue   (new on {spec})  create an issue from {source}")
        return 0, None
    created = fetch.api(spec, f"repos/{spec}/issues", "-f", f"title={values['title']}", "-f", f"body={values['body']}")
    now = nouns.now()
    owner, repo = created["html_url"].split("/")[3:5]
    with opened.write() as db:
        issue_id = fetch.Fetcher(opened, now).issue(owner, repo, created["number"])
        for name, value in values.items():
            store.set_base(db, issue_id, name, value, now)
        store.promote(db, issue_id, source)
        opened.touch(issue_id)
    return 0, created["html_url"]


def _finish(url, flags):
    print(url)
    if flags["open"]:
        browser.open_tab(url)


def run(context, args):
    parsed = parse(args)
    if parsed is None:
        return 0
    verb, target, flags = parsed
    rerun = "timvisher_gh issue" + ("" if verb == "sync" else f" {verb}")
    opened = state.open_state()
    try:
        store.exporting(opened, lambda object_id: record.record(opened.db, object_id), nouns.now)
        if context is not None:
            adopt.adopt_root(opened, context.toplevel, pr._lookup, nouns.now())
            adopt.adopt_directory(opened, context.toplevel, "issue", pr._lookup, nouns.now())
        found = targets.resolve("issue", target, context=context, db=opened.db, creating=True)
        if found.kind == "source":
            if verb == "edit":
                fail("timvisher_gh_issue_missing", f"There's no issue for {found.source} to edit.",
                     suggestions=["Create it with 'timvisher_gh issue push' (or the bare 'timvisher_gh issue')"])
            if verb in ("fetch", "pull"):
                aictl.info(code="timvisher_gh_nothing_to_do",
                           message=f"There's no issue yet for {found.source}, so {verb} has nothing to do.",
                           suggestions=["Create it with 'timvisher_gh issue push'"])
                return 0
            if context is None:
                fail("timvisher_gh_target_none", "Creating an issue needs a worktree to name its repository.",
                     suggestions=["Run it in a worktree of the repository, or with -C <worktree>"])
            rc, url = _create(opened, context, found.source, flags)
            if url:
                _finish(url, flags)
            return rc
        if found.kind != "issue":
            usage(f"'{found.url}' names a {found.kind}, so issue can't use it.")
        now = nouns.now()
        fetcher = fetch.Fetcher(opened, now)
        with opened.write():
            issue_id = fetcher.issue(found.owner, found.repo, found.number)
        url = opened.db.execute("SELECT url FROM objects WHERE id = ?", (issue_id,)).fetchone()[0]
        if verb == "fetch":
            print(url)
            return 0
        raw = json.loads(opened.db.execute("SELECT payload FROM raw WHERE object_id = ?", (issue_id,)).fetchone()[0])
        viewer = fetcher.viewer(f"{found.owner}/{found.repo}")
        item = sync.Item(issue_id, "issue", url, IssueAdapter(opened, fetcher),
                         mine=raw["user"]["login"].lower() == viewer.lower())
        rc = sync.Engine(opened, verb, now=now, rerun=rerun, resolution=flags["resolution"], plan_only=flags["plan"],
                         ask=sync.prompt if sync.interactive() else None).run([item])
        if rc == 0 and not flags["plan"]:
            _finish(url, flags)
        return rc
    except fetch.NotFound as missing:
        fail("timvisher_gh_not_found", f"GitHub has no such issue ({missing}).",
             suggestions=["Check the URL, and that your gh account can see the repository"])
    finally:
        opened.close()
    return ERROR
