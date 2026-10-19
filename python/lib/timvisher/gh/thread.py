import json
import pathlib
import sys

from timvisher import aictl, browser
from timvisher.gh import adopt, comment, fetch, nouns, pr, record, state, store, sync, targets
from timvisher.gh.errors import ERROR, fail, usage

USAGE_TEXT = """\
Usage: timvisher_gh [-C <path>] thread [<target>] <file> [--path P --line N [--start-line M] [--side LEFT|RIGHT]]
       timvisher_gh [-C <path>] thread fetch|pull|push [<target>] [<file>]
       timvisher_gh [-C <path>] thread edit <file-or-target>
       timvisher_gh [-C <path>] thread resolve [--unresolve] <target>
       timvisher_gh [-C <path>] thread info <target> [<component>]

  thread [<target>] <file>  sync <file>, creating it on its first push. A PR target
                            (or none: the worktree's PR) plus --path and --line makes
                            a new review thread on that line (--side defaults to RIGHT,
                            the commit to the PR's head); a thread target updates its
                            root comment.
  edit <file-or-target>     update only: an error if the thread doesn't exist
  resolve [--unresolve] <target>
                            resolve or reopen; a no-op when GitHub already matches
  info <target> [<component>]  the record (see 'thread info --help')

Replies go through 'timvisher_gh comment' with the thread as the target.
Options for the syncing forms: --plan, --ours, --theirs, --merge, --open.
"""

RESOLVE = ("mutation ResolveReviewThread($threadId: ID!) { resolveReviewThread(input: {threadId: $threadId}) "
           "{ thread { isResolved } } }")
UNRESOLVE = ("mutation UnresolveReviewThread($threadId: ID!) { unresolveReviewThread(input: {threadId: $threadId}) "
             "{ thread { isResolved } } }")


def _parse(args):
    flags = {"plan": False, "resolution": None, "open": False, "unresolve": False, "path": None, "line": None,
             "start_line": None, "side": None}
    positionals, rest = [], list(args)
    while rest:
        arg = rest.pop(0)
        match arg:
            case "-h" | "--help":
                sys.stdout.write(USAGE_TEXT)
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
            case "--unresolve":
                flags["unresolve"] = True
            case "--path" | "--line" | "--start-line" | "--side":
                if not rest:
                    usage(f"{arg} requires a value")
                flags[arg[2:].replace("-", "_")] = rest.pop(0)
            case _ if arg.startswith("-"):
                usage(f"thread: unknown option '{arg}'", "See 'timvisher_gh thread --help'")
            case _:
                positionals.append(arg)
    for name in ("line", "start_line"):
        if flags[name] is not None:
            if not flags[name].isdigit():
                usage(f"--{name.replace('_', '-')} must be a line number, not '{flags[name]}'")
            flags[name] = int(flags[name])
    if flags["side"] is not None:
        flags["side"] = flags["side"].upper()
        if flags["side"] not in ("LEFT", "RIGHT"):
            usage(f"--side must be LEFT or RIGHT, not '{flags['side']}'")
    return positionals, flags


def _thread_node(spec, owner, repo, number, database_id):
    found = fetch.api(spec, "graphql", "-f", f"query={fetch.REVIEW_THREADS}", "-f", f"owner={owner}",
                      "-f", f"repo={repo}", "-F", f"number={number}")
    for node in found["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"]:
        if node["comments"]["nodes"] and node["comments"]["nodes"][0]["databaseId"] == database_id:
            return node
    return None


def _create(opened, where, source, flags, now):
    if flags["path"] is None or flags["line"] is None:
        usage("A new review thread needs --path and --line", "Or target an existing thread to update its root comment")
    spec = f"{where.owner}/{where.repo}"
    pr_id = comment._object(opened, targets.Target("pr", owner=where.owner, repo=where.repo, number=where.number), now)
    head = json.loads(opened.db.execute("SELECT payload FROM raw WHERE object_id = ?", (pr_id,)).fetchone()[0])
    body = sync.normalize(pathlib.Path(source).read_text(encoding="utf-8"))
    fields = ["-f", f"body={body}", "-f", f"path={flags['path']}", "-F", f"line={flags['line']}",
              "-f", f"side={flags['side'] or 'RIGHT'}", "-f", f"commit_id={head['head']['sha']}"]
    if flags["start_line"] is not None:
        fields += ["-F", f"start_line={flags['start_line']}", "-f", f"start_side={flags['side'] or 'RIGHT'}"]
    created = fetch.api(spec, f"repos/{spec}/pulls/{where.number}/comments", *fields)
    node = _thread_node(spec, where.owner, where.repo, where.number, created["id"])
    if node is None:
        fail("timvisher_gh_thread_unrecorded",
             f"Posted {created['html_url']}, but GitHub didn't list its thread, so {source} isn't tracked yet.",
             suggestions=[f"Run 'timvisher_gh pr pull {where.pr_url}', then track the thread from the store; "
                          f"don't rerun this command, or it posts again"])
    owner, repo = created["html_url"].split("/")[3:5]
    pr_key = opened.db.execute("SELECT store_path FROM objects WHERE id = ?", (pr_id,)).fetchone()[0]
    name = store.thread_name(created["created_at"], created["user"]["login"], created.get("path"), created.get("line"))
    with opened.write() as db:
        key = store.unique(store.root(), store.child_key(pr_key, "threads", name))
        store.register(db, id=node["id"], kind="thread", url=created["html_url"], owner=owner, repo=repo,
                       database_id=created["id"], parent_id=pr_id, store_path=key)
        db.execute("INSERT INTO raw VALUES (?, ?, ?) ON CONFLICT (object_id) DO UPDATE SET payload = excluded.payload",
                   (node["id"], json.dumps({"root": created, "thread": node}), now))
        store.set_base(db, node["id"], "body", body, now)
        store.set_remote(db, node["id"], "body", created["body"], now)
        store.set_remote(db, node["id"], "resolved", node["isResolved"], now)
        store.promote(db, node["id"], source)
        opened.touch(node["id"])
    return created["html_url"]


def _resolve(opened, found, unresolve, plan, now):
    object_id = comment._object(opened, found, now)
    if object_id is None or opened.db.execute("SELECT kind FROM objects WHERE id = ?", (object_id,)).fetchone()[0] != "thread":
        fail("timvisher_gh_not_found", f"GitHub has no review thread at {found.url}.",
             suggestions=["Address a thread by its root comment's #discussion_r<ID> URL"])
    spec = f"{found.owner}/{found.repo}"
    database_id = opened.db.execute("SELECT database_id FROM objects WHERE id = ?", (object_id,)).fetchone()[0]
    node = _thread_node(spec, found.owner, found.repo, found.number, database_id)
    wanted = not unresolve
    if plan:
        print(f"~ thread  {found.url}  {'unchanged' if node['isResolved'] == wanted else ('resolve' if wanted else 'reopen')}")
        return 0
    if node["isResolved"] != wanted:
        fetch.api(spec, "graphql", "-f", f"query={UNRESOLVE if unresolve else RESOLVE}", "-f", f"threadId={object_id}")
        node = _thread_node(spec, found.owner, found.repo, found.number, database_id)
    with opened.write() as db:
        store.set_remote(db, object_id, "resolved", node["isResolved"], now)
        payload = json.loads(db.execute("SELECT payload FROM raw WHERE object_id = ?", (object_id,)).fetchone()[0])
        db.execute("UPDATE raw SET payload = ? WHERE object_id = ?",
                   (json.dumps({**payload, "thread": {**payload.get("thread", {}), **node}}), object_id))
        opened.touch(object_id)
    if node["isResolved"] != wanted:
        aictl.error(code="timvisher_gh_resolve_failed", message=f"{found.url} is still "
                    f"{'resolved' if node['isResolved'] else 'unresolved'} after asking GitHub to change it.",
                    suggestions=["Rerun the same command"])
        return ERROR
    print(found.url)
    return 0


def run(context, args):
    verb = "sync"
    rest = list(args)
    if rest and rest[0] in ("fetch", "pull", "push", "edit", "resolve"):
        verb = rest.pop(0)
    parsed = _parse(rest)
    if parsed is None:
        return 0
    positionals, flags = parsed
    rerun = "timvisher_gh thread" + ("" if verb == "sync" else f" {verb}")
    opened = state.open_state()
    now = nouns.now()
    try:
        store.exporting(opened, lambda object_id: record.record(opened.db, object_id), nouns.now)
        if verb == "resolve":
            if len(positionals) != 1:
                usage("thread resolve needs one <target>")
            found = targets.resolve("thread", positionals[0], context=context, db=opened.db)
            if found.kind != "thread":
                usage(f"'{found.url}' names a {found.kind}, so thread resolve can't use it.")
            return _resolve(opened, found, flags["unresolve"], flags["plan"], now)

        if verb == "edit" and len(positionals) == 1:
            target_arg, file_arg = None, positionals[0]
        elif verb in ("fetch", "pull", "push") and len(positionals) == 1 and (
                positionals[0] == targets.BROWSER_TAB or positionals[0].startswith("https://")):
            target_arg, file_arg = None, positionals[0]
        elif len(positionals) == 2 and verb != "edit":
            target_arg, file_arg = positionals
        elif len(positionals) == 1 and verb != "edit":
            target_arg, file_arg = None, positionals[0]
        else:
            usage(f"thread {'' if verb == 'sync' else verb + ' '}needs a <file>", "See 'timvisher_gh thread --help'")

        if context is not None:
            adopt.adopt_root(opened, context.toplevel, pr._lookup, now)
            adopt.adopt_directory(opened, context.toplevel, "pr", pr._lookup, now)
        tracked = targets.resolve("thread", file_arg, context=context, db=opened.db, creating=True)
        if tracked.kind not in ("thread", "source"):
            usage(f"'{file_arg}' names a {tracked.kind}, so thread can't use it.",
                  "Reply to a thread with 'timvisher_gh comment reply <thread> <file>'")
        if target_arg is not None:
            where = targets.resolve("thread", target_arg, context=context, db=opened.db)
        elif tracked.kind == "source" and verb != "edit":
            where = targets.resolve("thread", None, context=context, db=opened.db)
        else:
            where = None
        if where is not None and where.kind not in ("pr", "thread"):
            usage(f"'{where.url}' names a {where.kind}, so thread can't use it.")

        if tracked.kind == "source":
            if verb in ("fetch", "pull"):
                aictl.info(code="timvisher_gh_nothing_to_do",
                           message=f"{file_arg} isn't posted yet, so {verb} has nothing to do.")
                return 0
            if verb == "edit":
                fail("timvisher_gh_thread_missing", f"{file_arg} isn't a posted thread, so there's nothing to edit.",
                     suggestions=[f"Create it with 'timvisher_gh thread <pr> {file_arg} --path P --line N'"])
            if where.kind == "thread":
                usage(f"{file_arg} isn't tracked; to update {where.url}'s root comment, edit its store file",
                      f"Or reply with 'timvisher_gh comment reply {where.url} {file_arg}'")
            if flags["plan"]:
                print(f"+ thread  (new on {where.pr_url} at {flags['path']}:{flags['line']})  post {file_arg}")
                return 0
            url = _create(opened, where, file_arg, flags, now)
            print(url)
            if flags["open"]:
                browser.open_tab(url)
            return 0

        object_id = tracked.object_id or comment._object(opened, tracked, now)
        if where is not None and where.kind == "thread" and comment._object(opened, where, now) != object_id:
            usage(f"{file_arg} is already {tracked.url}'s root comment, not {where.url}'s.")
        number = opened.db.execute("SELECT o.number FROM objects o JOIN objects t ON t.parent_id = o.id "
                                   "WHERE t.id = ?", (object_id,)).fetchone()[0]
        if verb in ("fetch", "pull", "sync"):
            with opened.write():
                fetch.Fetcher(opened, now).pr(tracked.owner, tracked.repo, number)
        viewer = fetch.api(f"{tracked.owner}/{tracked.repo}", "user")["login"]
        url = opened.db.execute("SELECT url FROM objects WHERE id = ?", (object_id,)).fetchone()[0]
        if verb == "fetch":
            print(url)
            return 0
        item = sync.Item(object_id, "thread", url, comment.CommentAdapter(opened, now),
                         mine=comment._mine(opened.db, object_id, viewer))
        rc = sync.Engine(opened, {"edit": "edit"}.get(verb, verb), now=now, rerun=rerun,
                         resolution=flags["resolution"], plan_only=flags["plan"],
                         ask=sync.prompt if sync.interactive() else None).run([item])
        if rc == 0 and not flags["plan"]:
            print(url)
            if flags["open"]:
                browser.open_tab(url)
        return rc
    except fetch.NotFound as missing:
        fail("timvisher_gh_not_found", f"GitHub has no such thread or PR ({missing}).",
             suggestions=["Check the URL, and that your gh account can see the repository"])
    finally:
        opened.close()
    return ERROR
