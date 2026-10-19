import json

from timvisher.gh import store

SCHEMA_VERSION = 1

REACTIONS = ("+1", "-1", "laugh", "confused", "heart", "hooray", "rocket", "eyes")

FIELDS = {
    "common": (
        ("schema_version", "this record's contract version (§8.1)"),
        ("kind", "pr, issue, comment, thread or review"),
        ("url", "the object's GitHub URL"),
        ("id", "GitHub node ID"),
        ("database_id", "GitHub database ID"),
        ("owner", "repository owner"),
        ("repo", "repository name"),
        ("author", "the author's login"),
        ("created_at", "creation time, as GitHub reports it"),
        ("updated_at", "last update time, as GitHub reports it"),
        ("deleted_at", "when it was seen deleted upstream, or null"),
        ("source", "{path, authored_paths}: the store file and the authored symlinks to it"),
        ("posted", "the last values pushed or agreed (the lease)"),
        ("github", "the raw last GitHub response; no compatibility promise"),
    ),
    "pr": (
        ("number", "PR number"), ("title", "title"), ("body", "body"),
        ("state", "open, closed or merged"), ("draft", "true or false"), ("base", "base branch"),
        ("head", "head branch"), ("head_sha", "head commit"), ("merged_at", "merge time or null"),
        ("merge_commit", "merge commit or null"), ("comments", "top-level comment URLs"),
        ("threads", "review thread URLs (their root comments')"), ("reviews", "review URLs"),
    ),
    "issue": (
        ("number", "issue number"), ("title", "title"), ("body", "body"), ("state", "open or closed"),
        ("closed_at", "close time or null"),
    ),
    "comment": (
        ("comment_kind", "issue_comment or review_comment"), ("pr", "the PR's record, without its children"),
        ("thread", "the thread's record for a review comment, without its children, or null"),
        ("in_reply_to", "the thread root's URL for a reply, or null"), ("body", "body"),
        ("reactions", "your reactions, REST names, sorted"), ("reaction_counts", "count per reaction"),
    ),
    "thread": (
        ("pr", "the PR's record, without its children"), ("path", "anchor path"), ("line", "anchor line"),
        ("start_line", "first line of a multi-line anchor, or null"), ("side", "LEFT or RIGHT"),
        ("commit", "the anchored commit"), ("outdated", "true or false"), ("resolved", "true or false"),
        ("root", "the root comment's URL"), ("replies", "reply URLs"),
    ),
    "review": (
        ("pr", "the PR's record, without its children"), ("state", "the review state"), ("body", "body"),
        ("submitted_at", "submission time"),
    ),
}

COMPATIBILITY = """\
Compatibility (§8.1): schema_version covers every kind, embedded parents
included. Adding a field or a kind keeps the version, so ignore fields you
don't know. Removing or renaming a field, changing a field's type, format
or meaning, making a field nullable, or adding a value to an enumerated
field (state, comment_kind, side, ...) bumps it. 'github' carries no promise.
Pin with --schema-version <N>.

Schema versions:
  1  the first version; no breaking changes yet."""


def _row(db, object_id):
    columns = ("id", "kind", "url", "owner", "repo", "number", "database_id", "parent_id", "store_path", "deleted_at")
    row = db.execute(f"SELECT {', '.join(columns)} FROM objects WHERE id = ?", (object_id,)).fetchone()
    return dict(zip(columns, row))


def _values(db, object_id, column):
    return {name: json.loads(value) for name, value in
            db.execute(f"SELECT name, {column} FROM fields WHERE object_id = ? AND {column} IS NOT NULL", (object_id,))}


def _raw(db, object_id):
    row = db.execute("SELECT payload FROM raw WHERE object_id = ?", (object_id,)).fetchone()
    return json.loads(row[0]) if row else {}


def _children(db, object_id, kind):
    return [url for (url,) in db.execute("SELECT url FROM objects WHERE parent_id = ? AND kind = ? "
                                         "ORDER BY database_id, url", (object_id, kind))]


def _counts(summary):
    return {name: (summary or {}).get(name, 0) for name in REACTIONS}


def record(db, object_id, children=True):
    row = _row(db, object_id)
    raw, remote = _raw(db, object_id), _values(db, object_id, "remote")
    kind = row["kind"]
    comment = raw.get("root", {}) if kind == "thread" else raw
    stored = store.store_file(db, object_id)
    authored = [path for (path,) in db.execute("SELECT path FROM authored WHERE object_id = ? ORDER BY path",
                                               (object_id,))]
    result = {
        "schema_version": SCHEMA_VERSION, "kind": kind, "url": row["url"], "id": row["id"],
        "database_id": row["database_id"], "owner": row["owner"], "repo": row["repo"],
        "author": (comment.get("user") or {}).get("login"),
        "created_at": comment.get("submitted_at") if kind == "review" else comment.get("created_at"),
        "updated_at": comment.get("updated_at"), "deleted_at": row["deleted_at"],
        "source": {"path": str(stored) if stored.exists() else None, "authored_paths": authored},
        "posted": _values(db, object_id, "base"),
        "github": raw,
    }
    parent = row["parent_id"]
    match kind:
        case "pr":
            result.update(number=row["number"], title=remote.get("title"), body=remote.get("body"),
                          state=remote.get("state"), draft=remote.get("draft"), base=remote.get("base"),
                          head=raw.get("head", {}).get("ref"), head_sha=raw.get("head", {}).get("sha"),
                          merged_at=raw.get("merged_at"), merge_commit=raw.get("merge_commit_sha"))
            if children:
                result.update(comments=_children(db, object_id, "comment"), threads=_children(db, object_id, "thread"),
                              reviews=_children(db, object_id, "review"))
        case "issue":
            result.update(number=row["number"], title=remote.get("title"), body=remote.get("body"),
                          state=remote.get("state"), closed_at=raw.get("closed_at"))
        case "comment":
            thread_id = parent if _row(db, parent)["kind"] == "thread" else None
            pr_id = _row(db, thread_id)["parent_id"] if thread_id else parent
            result.update(comment_kind="review_comment" if thread_id else "issue_comment",
                          pr=record(db, pr_id, children=False),
                          thread=record(db, thread_id, children=False) if thread_id else None,
                          in_reply_to=_row(db, thread_id)["url"] if thread_id else None,
                          body=remote.get("body"), reactions=remote.get("reactions", []),
                          reaction_counts=_counts(raw.get("reactions")))
        case "thread":
            node = raw.get("thread", {})
            result.update(pr=record(db, parent, children=False), path=comment.get("path"), line=comment.get("line"),
                          start_line=comment.get("start_line"), side=comment.get("side"),
                          commit=comment.get("commit_id"), outdated=node.get("isOutdated"),
                          resolved=remote.get("resolved"), root=row["url"])
            if children:
                result["replies"] = _children(db, object_id, "comment")
        case "review":
            result.update(pr=record(db, parent, children=False), state=remote.get("state"),
                          body=remote.get("body"), submitted_at=raw.get("submitted_at"))
    return result


def as_comment(db, thread_id):
    thread = record(db, thread_id)
    root = thread["github"]["root"]
    remote = _values(db, thread_id, "remote")
    return {key: thread[key] for key in ("schema_version", "url", "owner", "repo", "author", "created_at",
                                         "updated_at", "deleted_at", "source", "posted", "pr")} | {
        "kind": "comment", "id": root["node_id"], "database_id": root["id"], "github": root,
        "comment_kind": "review_comment", "thread": record(db, thread_id, children=False), "in_reply_to": None,
        "body": remote.get("body"), "reactions": remote.get("reactions", []),
        "reaction_counts": _counts(root.get("reactions")),
    }
