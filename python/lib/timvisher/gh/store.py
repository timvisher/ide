import datetime
import re
import unicodedata

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
