import json
import os
import pathlib
import shutil
import subprocess

from timvisher.gh import store, targets
from timvisher.gh.errors import USAGE, fail


def _object_for(db, url):
    row = db.execute("SELECT id FROM objects WHERE url = ?", (url,)).fetchone()
    return row and row[0]


def ensure_parent(db, target, lookup):
    kind = "issue" if target.kind == "issue" else "pr"
    url = target.url if kind == "issue" else target.pr_url
    found = _object_for(db, url)
    if found:
        return found
    parent = targets.Target(kind, owner=target.owner, repo=target.repo, number=target.number)
    facts = lookup(parent)
    key = (store.issue_key if kind == "issue" else store.pr_key)(target.owner, target.repo, target.number)
    store.register(db, id=facts["id"], kind=kind, url=url, owner=target.owner, repo=target.repo,
                   number=target.number, database_id=facts.get("database_id"), store_path=key)
    return facts["id"]


def _record_context(db, worktree, pr_id):
    owner, repo = db.execute("SELECT owner, repo FROM objects WHERE id = ?", (pr_id,)).fetchone()
    branch = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=worktree, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, text=True).stdout.strip()
    db.execute("INSERT INTO context VALUES (?, ?, ?, ?, ?) ON CONFLICT (worktree) DO UPDATE SET "
               "owner = excluded.owner, repo = excluded.repo, branch = excluded.branch, pr_id = excluded.pr_id",
               (str(worktree), owner, repo, None if branch in ("", "HEAD") else branch, pr_id))


def link_context(db, worktree, pr_id):
    _record_context(db, worktree, pr_id)
    link = pathlib.Path(worktree) / ".timvisher_gh" / "pr"
    target = store.store_file(db, pr_id).parent
    target.mkdir(parents=True, exist_ok=True)
    if not link.is_symlink() or link.resolve() != target.resolve():
        store._link(link, target)


def _read_url(path):
    return path.read_text(encoding="utf-8").strip()


def _merged(db, pr_id, path, now):
    if os.path.lexists(path) and pr_id is not None:
        store.set_remote(db, pr_id, "state", "merged", now)
        path.unlink()


def adopt_root(state, worktree, lookup, now):
    worktree = pathlib.Path(worktree)
    pr_id = None
    for kind in ("pr", "issue"):
        source, url_file = worktree / f"{kind}.md", worktree / f"{kind}.md.url"
        if not (url_file.is_file() and not url_file.is_symlink()):
            continue
        target = targets.parse_url(_read_url(url_file), kind, f" (from {url_file})")
        with state.write() as db:
            object_id = ensure_parent(db, target, lookup)
            state.touch(object_id)
            if source.is_file() and not source.is_symlink():
                store.promote(db, object_id, source)
            if kind == "pr":
                link_context(db, worktree, object_id)
                pr_id = object_id
        exported = store.store_file(state.db, object_id).parent / f"{kind}.url"
        store._link(url_file, exported)
    merged = worktree / "x.merged"
    if merged.is_file() and not merged.is_symlink():
        if pr_id is None:
            row = state.db.execute("SELECT pr_id FROM context WHERE worktree = ?", (str(worktree),)).fetchone()
            pr_id = row and row[0]
        with state.write() as db:
            _merged(db, pr_id, merged, now)
    return pr_id


def _comment_object(db, pr_id, pr_target, item, now, threads, taken):
    kind = item.get("kind")
    posted = item.get("posted") or {}
    body = item.get("body", posted.get("body", ""))
    pr_key = store.pr_key(pr_target.owner, pr_target.repo, pr_target.number)
    common = {"owner": pr_target.owner, "repo": pr_target.repo, "database_id": item.get("database_id")}
    if kind == "issue_comment":
        key = store.child_key(pr_key, "comments", store.comment_name(item["created_at"], item["author"],
                                                                     body))
        object_id, parent, object_kind = item["id"], pr_id, "comment"
    elif kind == "review_comment" and not item.get("in_reply_to"):
        key = store.child_key(pr_key, "threads", store.thread_name(item["created_at"], item["author"],
                                                                   item.get("path"), item.get("line")))
        object_id, parent, object_kind = item["thread_id"], pr_id, "thread"
    elif kind == "review_comment":
        thread_key = threads.get(item["thread_id"])
        if thread_key is None:
            return None
        key = store.child_key(thread_key, "replies", store.comment_name(item["created_at"], item["author"],
                                                                        body))
        object_id, parent, object_kind = item["id"], item["thread_id"], "comment"
    elif kind == "review":
        key = store.child_key(pr_key, "reviews", store.review_name(item["created_at"], item["author"]))
        object_id, parent, object_kind = item["id"], pr_id, "review"
    else:
        return None
    existing = db.execute("SELECT store_path FROM objects WHERE id = ?", (object_id,)).fetchone()
    key = existing[0] if existing else store.unique(store.root(), key, taken)
    taken.add(key)
    store.register(db, id=object_id, kind=object_kind, url=item["url"], parent_id=parent, store_path=key, **common)
    if "body" in posted:
        store.set_base(db, object_id, "body", posted["body"], now)
    if "resolved" in posted:
        store.set_remote(db, object_id, "resolved", posted["resolved"], now)
    if "reactions" in posted:
        store.set_remote(db, object_id, "reactions", posted["reactions"], now)
    if object_kind == "thread":
        threads[object_id] = key
    return object_id


def _sidecars(directory):
    items = []
    for sidecar in sorted(directory.rglob("*.md.json")):
        try:
            item = json.loads(sidecar.read_text(encoding="utf-8"))
        except ValueError:
            continue
        if isinstance(item, dict) and item.get("url"):
            items.append((sidecar, item))
    order = {"issue_comment": 0, "review": 0, "review_comment": 1}
    return sorted(items, key=lambda pair: (order.get(pair[1].get("kind"), 2), bool(pair[1].get("in_reply_to"))))


def _move(source, target):
    if os.path.lexists(source):
        store.merge_move(source, target)


def adopt_pr_directory(state, worktree, lookup, now):
    worktree = pathlib.Path(worktree)
    directory = worktree / ".timvisher_gh" / "pr"
    if directory.is_symlink() or not directory.is_dir():
        return None
    meta_file = directory / "pr.json"
    meta = json.loads(meta_file.read_text(encoding="utf-8")) if meta_file.is_file() else {}
    if not meta.get("url"):
        return None
    pr_target = targets.parse_url(meta["url"], "pr", f" (from {meta_file})")
    items = _sidecars(directory / "comments")
    moves = []
    with state.write() as db:
        pr_id = ensure_parent(db, pr_target, lookup)
        state.touch(pr_id)
        posted = meta.get("posted") or {}
        for name in ("title", "body"):
            if name in posted:
                store.set_base(db, pr_id, name, posted[name], now)
        pr_dir = store.root() / store.pr_key(pr_target.owner, pr_target.repo, pr_target.number)
        threads, taken = {}, set()
        for sidecar, item in items:
            object_id = _comment_object(db, pr_id, pr_target, item, now, threads, taken)
            if object_id is not None:
                state.touch(object_id)
                moves.append((sidecar, store.store_file(db, object_id)))
        _merged(db, pr_id, directory / "merged", now)
        _record_context(db, worktree, pr_id)
    for sidecar, target in moves:
        _move(sidecar.with_suffix(""), target)
        sidecar.unlink()
        sidecar.with_suffix(".url").unlink(missing_ok=True)
    _move(directory / "pr.md", pr_dir / "pr.md")
    for leftover in ("pr.json", "pr.url"):
        (directory / leftover).unlink(missing_ok=True)
    for path in sorted(directory.rglob("*"), reverse=True):
        if path.is_file() or path.is_symlink():
            _move(path, pr_dir / path.relative_to(directory))
    shutil.rmtree(directory)
    pr_dir.mkdir(parents=True, exist_ok=True)
    store._link(directory, pr_dir)
    if (worktree / "x.merged").is_symlink():
        (worktree / "x.merged").unlink()
    with state.write() as db:
        for link in ("pr.md",):
            if (worktree / link).is_symlink():
                db.execute("INSERT OR IGNORE INTO authored VALUES (?, ?)", (pr_id, str(worktree / link)))
        state.touch(pr_id)
    return pr_id


def adopt_comment(state, path, lookup, now):
    path = pathlib.Path(path)
    sidecar, url_file = path.with_name(path.name + ".json"), path.with_name(path.name + ".url")
    item = {}
    if sidecar.is_file():
        item = json.loads(sidecar.read_text(encoding="utf-8"))
        url = item.get("url")
    elif url_file.is_file():
        url = _read_url(url_file)
    else:
        return None
    target = targets.parse_url(url, "comment", f" (from {sidecar if item else url_file})")
    if target.kind not in ("comment", "review_comment"):
        fail("timvisher_gh_adopt_not_a_comment", f"'{path}' is recorded as {url}, which isn't a comment.",
             status=USAGE, suggestions=["Fix or remove its sidecar, then rerun"])
    with state.write() as db:
        pr_id = ensure_parent(db, target, lookup)
        existing = _object_for(db, target.url)
        if existing is None:
            facts = lookup(target)
            if facts.get("thread") and _object_for(db, facts["thread"]["url"]) is None:
                thread = facts["thread"]
                _comment_object(db, pr_id, target, {**thread, "kind": "review_comment", "in_reply_to": None},
                                now, {}, set())
            threads = dict(db.execute("SELECT id, store_path FROM objects WHERE kind = 'thread'"))
            facts = {**facts, "url": target.url, "posted": item.get("posted") or {}}
            existing = _comment_object(db, pr_id, target, facts, now, threads, set())
        state.touch(existing)
        stored = store.promote(db, existing, path)
    for legacy, export in ((sidecar, "comment.json"), (url_file, "comment.url")):
        if legacy.is_file() and not legacy.is_symlink():
            store._link(legacy, stored.parent / export)
    return existing
