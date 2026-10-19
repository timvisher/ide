import json
import pathlib
import re
import subprocess
import sys

from timvisher import aictl, browser
from timvisher.gh import adopt, fetch, nouns, record, state, store, sync, targets
from timvisher.gh.errors import ERROR, fail, usage

VERBS = ("fetch", "pull", "push", "edit")

USAGE = """\
Usage: timvisher_gh [-C <path>] pr [fetch|pull|push|edit] [<target>] [options]
       timvisher_gh [-C <path>] pr info [<target>] [<component>]

  pr [<target>]       sync: pull, then push
  pr fetch            update the state for the PR and its conversation; writes no files
  pr pull             fetch, then write GitHub's changes into the store, for objects
                      whose source is unchanged
  pr push             fetch, then push the branch and the description, creating a
                      draft PR from the source if there is none
  pr edit             as push, but an error if the PR doesn't exist

Options: --plan, --ours, --theirs, --merge, --open, --draft, --ready-for-review,
         --base <branch>

The source is <toplevel>/pr.md: the title on line 1, the body from line 3.
"""

MARK_READY = ("mutation MarkPullRequestReadyForReview($id: ID!) { markPullRequestReadyForReview(input: "
              "{pullRequestId: $id}) { pullRequest { isDraft } } }")
TO_DRAFT = ("mutation ConvertPullRequestToDraft($id: ID!) { convertPullRequestToDraft(input: "
            "{pullRequestId: $id}) { pullRequest { isDraft } } }")


def parse_source(text):
    lines = text.replace("\r\n", "\n").split("\n")
    return {"title": lines[0], "body": "\n".join(lines[2:]).rstrip("\n")}


def source_state(db, object_id):
    return {name.removeprefix("source."): json.loads(value) for name, value in
            db.execute("SELECT name, base FROM fields WHERE object_id = ? AND name LIKE 'source.%'", (object_id,))}


def set_source_state(db, object_id, values, now):
    for name, value in values.items():
        store.set_base(db, object_id, f"source.{name}", value, now)


class PrAdapter:
    managed = ("title", "body", "draft", "base")

    def __init__(self, opened, fetcher, flags):
        self.state = opened
        self.fetcher = fetcher
        self.flags = flags

    def _row(self, item):
        return self.state.db.execute("SELECT owner, repo, number FROM objects WHERE id = ?",
                                     (item.object_id,)).fetchone()

    def fetch(self, item):
        owner, repo, number = self._row(item)
        self.fetcher.pr(owner, repo, number, conversation=False)
        raw = json.loads(self.state.db.execute("SELECT payload FROM raw WHERE object_id = ?",
                                               (item.object_id,)).fetchone()[0])
        return {"title": raw["title"], "body": raw.get("body") or "", "draft": raw["draft"],
                "base": raw["base"]["ref"]}

    def read_source(self, item):
        db = self.state.db
        path = store.store_file(db, item.object_id)
        store.backfill(db, item.object_id)
        values = parse_source(path.read_text(encoding="utf-8"))
        values.update(source_state(db, item.object_id))
        for name in ("draft", "base"):
            if self.flags.get(name) is not None:
                values[name] = self.flags[name]
        if "draft" not in values or "base" not in values:
            bases = store.bases(db, item.object_id)
            values.setdefault("draft", bases.get("draft"))
            values.setdefault("base", bases.get("base"))
        return values

    def write_source(self, item, values):
        db = self.state.db
        path = store.store_file(db, item.object_id)
        store._write_atomic(path, store.source_text("pr", values))
        set_source_state(db, item.object_id, {n: values[n] for n in ("draft", "base") if n in values},
                         self.fetcher.now)

    def push(self, item, values):
        owner, repo, number = self._row(item)
        spec = f"{owner}/{repo}"
        patch = [arg for name in ("title", "body", "base") if name in values
                 for arg in ("-f", f"{name}={values[name]}")]
        if patch:
            fetch.api(spec, "-X", "PATCH", f"repos/{spec}/pulls/{number}", *patch)
        if "draft" in values:
            fetch.api(spec, "graphql", "-f", f"query={TO_DRAFT if values['draft'] else MARK_READY}",
                      "-f", f"id={item.object_id}")
        set_source_state(self.state.db, item.object_id,
                         {n: values[n] for n in ("draft", "base") if n in values}, self.fetcher.now)


class ConversationAdapter:
    managed = ("body",)

    def __init__(self, opened):
        self.state = opened

    def fetch(self, item):
        remote = self.state.db.execute("SELECT remote FROM fields WHERE object_id = ? AND name = 'body'",
                                       (item.object_id,)).fetchone()
        return {"body": json.loads(remote[0]) if remote and remote[0] is not None else ""}

    def read_source(self, item):
        db = self.state.db
        store.backfill(db, item.object_id)
        return {"body": store.store_file(db, item.object_id).read_text(encoding="utf-8")}

    def write_source(self, item, values):
        store._write_atomic(store.store_file(self.state.db, item.object_id), store.source_text(item.kind, values))

    def push(self, item, values):
        raise NotImplementedError("conversation objects are pushed by the comment and thread nouns")


def _git(*args, cwd):
    return subprocess.run(["git", *args], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          text=True).stdout.strip()


def _lookup(target):
    spec = f"{target.owner}/{target.repo}"
    kind = "issues" if target.kind == "issue" else "pulls"
    found = fetch.api(spec, f"repos/{spec}/{kind}/{target.number}")
    return {"id": found["node_id"], "database_id": found.get("id")}


def parse(args):
    verb, target, flags = None, None, {"resolution": None, "plan": False, "open": False, "draft": None,
                                       "base": None}
    rest = list(args)
    if rest and rest[0] in VERBS:
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
            case "--draft":
                flags["draft"] = True
            case "--ready-for-review":
                flags["draft"] = False
            case "--base":
                if not rest:
                    usage("--base requires a <branch>")
                flags["base"] = rest.pop(0)
            case _ if arg.startswith("-"):
                usage(f"pr: unknown option '{arg}'", "See 'timvisher_gh pr --help'")
            case _ if target is None:
                target = arg
            case _:
                usage(f"pr: unexpected argument '{arg}'", "See 'timvisher_gh pr --help'")
    return verb or "sync", target, flags


def _is_worktree_pr(context, opened, object_id):
    if context is None:
        return False
    raw = json.loads(opened.db.execute("SELECT payload FROM raw WHERE object_id = ?", (object_id,)).fetchone()[0])
    branch = _git("rev-parse", "--abbrev-ref", "HEAD", cwd=context.toplevel)
    return raw["head"]["ref"] == branch and raw["base"]["repo"]["full_name"].lower() == context.spec.lower()


def _push_branch(context, flags):
    args = ["timvisher_git", "push"]
    if flags["resolution"] == "ours":
        args.append("--ours")
    if flags["plan"]:
        args.append("--plan")
    return subprocess.run(args, cwd=context.toplevel).returncode


def _head(context):
    branch = _git("rev-parse", "--abbrev-ref", "HEAD", cwd=context.toplevel)
    if not branch or branch == "HEAD":
        fail("timvisher_gh_pr_no_branch", "Creating a PR needs a branch, and this worktree's HEAD is detached.",
             suggestions=["Check out the branch the PR is for, then rerun"])
    origin = _git("remote", "get-url", "origin", cwd=context.toplevel)
    origin_owner = (re.sub(r"\.git$", "", origin).replace(":", "/").split("/")[-2]
                    if origin else context.spec.split("/")[0])
    owner = context.spec.split("/")[0]
    return branch, branch if origin_owner.lower() == owner.lower() else f"{origin_owner}:{branch}"


def _create(opened, context, source, flags):
    branch, head = _head(context)
    values = parse_source(pathlib.Path(source).read_text(encoding="utf-8"))
    spec = context.spec
    if flags["plan"]:
        print(f"+ pr      (new on {spec} from {head})  create {'a draft ' if flags['draft'] is not False else ''}"
              f"PR from {source}")
        return 0, None
    rc = _push_branch(context, flags)
    if rc != 0:
        return rc, None
    base = flags["base"] or fetch.api(spec, f"repos/{spec}")["default_branch"]
    draft = flags["draft"] is not False
    created = fetch.api(spec, f"repos/{spec}/pulls", "-f", f"title={values['title']}", "-f",
                        f"body={values['body']}", "-f", f"head={head}", "-f", f"base={base}", "-F",
                        f"draft={'true' if draft else 'false'}")
    now = nouns.now()
    fetcher = fetch.Fetcher(opened, now)
    owner, repo = created["html_url"].split("/")[3:5]
    with opened.write() as db:
        pr_id = fetcher.pr(owner, repo, created["number"], conversation=False)
        for name, value in {**values, "draft": draft, "base": base}.items():
            store.set_base(db, pr_id, name, value, now)
        set_source_state(db, pr_id, {"draft": draft, "base": base}, now)
        store.promote(db, pr_id, source)
        adopt.link_context(db, context.toplevel, pr_id)
        opened.touch(pr_id)
    return 0, created["html_url"]


def _conversation_items(opened, pr_id, viewer):
    db = opened.db
    adapter = ConversationAdapter(opened)
    rows = db.execute(
        "SELECT o.id, o.kind, o.url, r.payload FROM objects o JOIN raw r ON r.object_id = o.id "
        "WHERE o.deleted_at IS NULL AND o.store_path NOT LIKE 'archive/%' AND (o.parent_id = ? OR o.parent_id IN "
        "(SELECT id FROM objects WHERE parent_id = ? AND kind = 'thread')) ORDER BY o.database_id",
        (pr_id, pr_id)).fetchall()
    items = []
    for object_id, kind, url, payload in rows:
        raw = json.loads(payload)
        author = (raw.get("root") or raw).get("user", {}).get("login")
        items.append(sync.Item(object_id, kind, url, adapter,
                               mine=kind != "review" and (author or "").lower() == viewer.lower()))
    return items


def run(context, args):
    parsed = parse(args)
    if parsed is None:
        return 0
    verb, target, flags = parsed
    rerun = "timvisher_gh pr" + ("" if verb == "sync" else f" {verb}")
    opened = state.open_state()
    try:
        store.exporting(opened, lambda object_id: record.record(opened.db, object_id), nouns.now)
        if context is not None:
            adopt.adopt_root(opened, context.toplevel, _lookup, nouns.now())
            adopt.adopt_directory(opened, context.toplevel, "pr", _lookup, nouns.now())
        found = targets.resolve("pr", target, context=context, db=opened.db, creating=True)
        if found.kind == "source":
            if verb == "edit":
                fail("timvisher_gh_pr_missing", f"There's no PR for {found.source} to edit.",
                     suggestions=["Create it with 'timvisher_gh pr push' (or the bare 'timvisher_gh pr')"])
            if verb in ("fetch", "pull"):
                aictl.info(code="timvisher_gh_nothing_to_do",
                           message=f"There's no PR yet for {found.source}, so {verb} has nothing to do.",
                           suggestions=["Create it with 'timvisher_gh pr push'"])
                return 0
            if context is None:
                fail("timvisher_gh_target_none", "Creating a PR needs a worktree.",
                     suggestions=["Run it in the PR's worktree, or with -C <worktree>"])
            rc, url = _create(opened, context, found.source, flags)
            if url:
                print(url)
                if flags["open"]:
                    browser.open_tab(url)
            return rc
        if found.kind not in nouns.ACCEPTS["pr"]:
            usage(f"'{found.url}' names a {found.kind}, so pr can't use it.")
        object_id = nouns._object_id(opened.db, found, "pr")
        now = nouns.now()
        fetcher = fetch.Fetcher(opened, now)
        with opened.write():
            pr_id = fetcher.pr(found.owner, found.repo, found.number, conversation=verb in ("fetch", "pull", "sync"))
        object_id = object_id or pr_id
        url = opened.db.execute("SELECT url FROM objects WHERE id = ?", (object_id,)).fetchone()[0]
        viewer = fetcher.viewer(f"{found.owner}/{found.repo}")
        worktree_pr = _is_worktree_pr(context, opened, object_id)
        if worktree_pr and not flags["plan"]:
            with opened.write() as db:
                adopt.link_context(db, context.toplevel, object_id)
        if verb == "fetch":
            print(url)
            return 0
        if verb in ("pull", "sync"):
            items = _conversation_items(opened, object_id, viewer)
            if items:
                rc = sync.Engine(opened, "pull", now=now, rerun=rerun, resolution=flags["resolution"],
                                 plan_only=flags["plan"], ask=sync.prompt if sync.interactive() else None).run(items)
                if rc not in (0,):
                    return rc
        if verb in ("push", "sync", "edit") and worktree_pr:
            rc = _push_branch(context, flags)
            if rc != 0:
                return rc
        raw = json.loads(opened.db.execute("SELECT payload FROM raw WHERE object_id = ?", (object_id,)).fetchone()[0])
        item = sync.Item(object_id, "pr", url, PrAdapter(opened, fetcher, flags),
                         mine=raw["user"]["login"].lower() == viewer.lower())
        rc = sync.Engine(opened, verb, now=now, rerun=rerun, resolution=flags["resolution"], plan_only=flags["plan"],
                         ask=sync.prompt if sync.interactive() else None).run([item])
        given = {name: flags[name] for name in ("draft", "base") if flags[name] is not None}
        if rc == 0 and not flags["plan"] and given and verb in ("push", "sync", "edit"):
            with opened.write() as db:
                set_source_state(db, object_id, given, now)
        if rc == 0 and not flags["plan"]:
            print(url)
            if flags["open"]:
                browser.open_tab(url)
        return rc
    except fetch.NotFound as missing:
        fail("timvisher_gh_not_found", f"GitHub has no such PR ({missing}).",
             suggestions=["Check the URL, and that your gh account can see the repository"])
    finally:
        opened.close()
    return ERROR
