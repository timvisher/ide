import datetime
import json
import os
import pathlib
import re
import shutil
import unicodedata

from timvisher.gh import state as state_db

NAME_BYTES = 255
SLUG_CHARS = 60

FILES = {"pr": "pr.md", "issue": "issue.md", "comment": "comment.md", "thread": "root-comment.md",
         "review": "review.md"}


def stamp(created_at):
    when = datetime.datetime.fromisoformat(created_at).astimezone(datetime.timezone.utc)
    return when.strftime("%Y-%m-%dT%H-%M-%S%z")


def author(login):
    return re.sub(r"-+", "-", re.sub(r"[^A-Za-z0-9-]", "-", login or "")).strip("-")


def _clean(text):
    spaced = "".join(" " if unicodedata.category(c) == "Cc" or c == "/" else c for c in text or "")
    collapsed = re.sub(r"\s+", " ", spaced)
    return re.sub(r"[ .]+$", "", re.sub(r"^[ .-]+", "", collapsed))


def slug(text):
    return _clean(_clean(text)[:SLUG_CHARS])


def path_slug(path):
    return slug((path or "").replace("/", "-"))


def _name(head, cut, tail=()):
    def join(middle):
        return "-".join(part for part in (*head, middle, *tail) if part)

    while cut and NAME_BYTES < len(join(cut).encode("utf-8")):
        cut = _clean(cut[:-1])
    return join(cut)


def comment_name(created_at, login, body):
    return _name((stamp(created_at), author(login)), slug(body))


def thread_name(created_at, login, path, line):
    return _name((stamp(created_at), author(login)), path_slug(path), (f"L{line}",))


def review_name(created_at, login):
    return _name((stamp(created_at), author(login)), "", ("review",))


def pr_key(owner, repo, number):
    return f"github.com/{owner}/{repo}/pull/{number}"


def issue_key(owner, repo, number):
    return f"github.com/{owner}/{repo}/issues/{number}"


def child_key(parent_key, group, name):
    return f"{parent_key}/{group}/{name}"


# Two objects can share a name (same second, author and text); the later
# one gets -2, -3, ... rather than a hash, so names stay readable.
def unique(root, key, taken=()):
    candidate, n = key, 2
    while (root / candidate).exists() or candidate in taken:
        candidate = f"{key}-{n}"
        n += 1
    return candidate


def root():
    return state_db.root()


def _row(db, object_id):
    row = db.execute("SELECT id, kind, url, owner, repo, number, database_id, parent_id, store_path, deleted_at "
                     "FROM objects WHERE id = ?", (object_id,)).fetchone()
    if row is None:
        raise KeyError(object_id)
    return dict(zip(("id", "kind", "url", "owner", "repo", "number", "database_id", "parent_id", "store_path",
                     "deleted_at"), row))


def register(db, *, id, kind, url, owner, repo, store_path, number=None, database_id=None, parent_id=None):
    db.execute("INSERT INTO objects (id, kind, url, owner, repo, number, database_id, parent_id, store_path) "
               "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (id) DO UPDATE SET url = excluded.url",
               (id, kind, url, owner, repo, number, database_id, parent_id, store_path))


def set_base(db, object_id, name, value, at):
    db.execute("INSERT INTO fields (object_id, name, base, base_at) VALUES (?, ?, ?, ?) "
               "ON CONFLICT (object_id, name) DO UPDATE SET base = excluded.base, base_at = excluded.base_at",
               (object_id, name, json.dumps(value), at))


def set_remote(db, object_id, name, value, at):
    db.execute("INSERT INTO fields (object_id, name, remote, remote_at) VALUES (?, ?, ?, ?) "
               "ON CONFLICT (object_id, name) DO UPDATE SET remote = excluded.remote, remote_at = excluded.remote_at",
               (object_id, name, json.dumps(value), at))


def bases(db, object_id):
    return {name: json.loads(base) for name, base in
            db.execute("SELECT name, base FROM fields WHERE object_id = ? AND base IS NOT NULL", (object_id,))}


def store_file(db, object_id):
    row = _row(db, object_id)
    return root() / row["store_path"] / FILES[row["kind"]]


def source_text(kind, values):
    if kind in ("pr", "issue"):
        body = values.get("body") or ""
        return f"{values.get('title') or ''}\n\n{body}\n" if body else f"{values.get('title') or ''}\n"
    return f"{values.get('body') or ''}\n"


def _write_atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def _link(link, target):
    link.parent.mkdir(parents=True, exist_ok=True)
    tmp = link.with_name(f".{link.name}.tmp-link")
    if os.path.lexists(tmp):
        tmp.unlink()
    tmp.symlink_to(target)
    os.replace(tmp, link)


def promote(db, object_id, source):
    source = pathlib.Path(source).absolute()
    target = store_file(db, object_id)
    if not (source.is_symlink() and source.resolve() == target.resolve()):
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(source, target)
        _link(source, target)
    db.execute("INSERT OR IGNORE INTO authored (object_id, path) VALUES (?, ?)", (object_id, str(source)))
    return target


def backfill(db, object_id, fetch=None):
    restored = []
    target = store_file(db, object_id)
    if not target.exists():
        values = bases(db, object_id)
        if not values and fetch is not None:
            values = fetch()
        _write_atomic(target, source_text(_row(db, object_id)["kind"], values))
        restored.append(target)
    for (path,) in db.execute("SELECT path FROM authored WHERE object_id = ?", (object_id,)).fetchall():
        link = pathlib.Path(path)
        if not os.path.lexists(link):
            _link(link, target)
            restored.append(link)
    return restored


def archive(db, object_id, now):
    row = _row(db, object_id)
    key = row["store_path"]
    moved = [r[0] for r in db.execute("SELECT id FROM objects WHERE store_path = ? OR store_path LIKE ? ESCAPE '\\'",
                                      (key, key.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "/%"))]
    old, new = root() / key, root() / "archive" / key
    if old.exists():
        new.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(old, new)
    db.execute("UPDATE objects SET store_path = 'archive/' || store_path "
               f"WHERE id IN ({', '.join('?' * len(moved))})", moved)
    db.execute("UPDATE objects SET deleted_at = ? WHERE id = ?", (now, object_id))
    for moved_id in moved:
        for (path,) in db.execute("SELECT path FROM authored WHERE object_id = ?", (moved_id,)).fetchall():
            if pathlib.Path(path).is_symlink():
                _link(pathlib.Path(path), store_file(db, moved_id))
    return new


def export(db, object_ids, record_for, now):
    for object_id in sorted(object_ids):
        row = _row(db, object_id)
        directory = root() / row["store_path"]
        stem = row["kind"]
        _write_atomic(directory / f"{stem}.json", json.dumps(record_for(object_id), indent=2, ensure_ascii=False) + "\n")
        url_file = directory / f"{stem}.url"
        if url_file.exists() and url_file.read_text(encoding="utf-8").strip() != row["url"]:
            os.replace(url_file, directory / f"{stem}.url.bak.{now}")
        if not url_file.exists() or url_file.read_text(encoding="utf-8").strip() != row["url"]:
            _write_atomic(url_file, row["url"] + "\n")


def exporting(state, record_for, clock):
    state.after_commit = lambda touched: export(state.db, touched, record_for, clock())
