import dataclasses
import json
import os
import pathlib
import re
import subprocess

from timvisher import aictl, browser
from timvisher.gh import state as state_db
from timvisher.gh.errors import USAGE, fail

BROWSER_TAB = "current-browser-tab"

SHAPES = (
    "https://github.com/O/R/pull/N, optionally with /files, /changes or /commits, a ?query or a #fragment",
    "https://github.com/O/R/issues/N",
    "https://github.com/O/R/pull/N#issuecomment-<ID> (a top-level comment)",
    "https://github.com/O/R/pull/N#discussion_r<ID> (a review comment, or its thread with 'thread')",
)

_PULL = re.compile(r"https://github\.com/([^/?#]+)/([^/?#]+)/pull/(\d+)(?:/(?:files|changes|commits))?(?:\?[^#]*)?(?:#(.*))?")
_ISSUE = re.compile(r"https://github\.com/([^/?#]+)/([^/?#]+)/issues/(\d+)")
_ANCHOR = re.compile(r"(issuecomment-|discussion_r)(\d+)")


@dataclasses.dataclass(frozen=True)
class Target:
    kind: str
    owner: str | None = None
    repo: str | None = None
    number: int | None = None
    comment_id: int | None = None
    source: pathlib.Path | None = None
    object_id: str | None = None
    via: str = "url"

    @property
    def pr_url(self):
        return f"https://github.com/{self.owner}/{self.repo}/pull/{self.number}"

    @property
    def url(self):
        match self.kind:
            case "pr":
                return self.pr_url
            case "issue":
                return f"https://github.com/{self.owner}/{self.repo}/issues/{self.number}"
            case "comment":
                return f"{self.pr_url}#issuecomment-{self.comment_id}"
            case "review_comment" | "thread":
                return f"{self.pr_url}#discussion_r{self.comment_id}"
        return None


def _bad_url(url, came_from=""):
    fail("timvisher_gh_target_invalid_url", f"'{url}'{came_from} is not a GitHub URL timvisher_gh accepts.",
         status=USAGE, reason="Only github.com PR, issue and comment URLs are targets.",
         suggestions=[f"Use one of: {shape}" for shape in SHAPES])


def parse_url(url, noun, came_from=""):
    found = _match(url, noun)
    if found is None:
        _bad_url(url, came_from)
    return found


def _match(url, noun):
    if match := _PULL.fullmatch(url):
        owner, repo, number, fragment = match.groups()
        base = {"owner": owner, "repo": repo, "number": int(number)}
        anchor = _ANCHOR.fullmatch(fragment or "")
        if anchor is None:
            return Target("pr", **base)
        prefix, comment_id = anchor.groups()
        if prefix == "issuecomment-":
            if noun == "thread":
                fail("timvisher_gh_target_not_a_thread", f"'{url}' is a top-level comment, which has no thread.",
                     status=USAGE, suggestions=["Address a thread by its root comment's #discussion_r<ID> URL",
                                                "Use 'timvisher_gh comment' for a top-level comment"])
            return Target("comment", comment_id=int(comment_id), **base)
        return Target("thread" if noun == "thread" else "review_comment", comment_id=int(comment_id), **base)
    if match := _ISSUE.fullmatch(url):
        owner, repo, number = match.groups()
        return Target("issue", owner=owner, repo=repo, number=int(number))
    return None


def _browser_url():
    try:
        return browser.active_tab()["url"]
    except subprocess.CalledProcessError:
        fail("timvisher_gh_target_browser_failed", "Unable to read the current browser tab's URL.",
             suggestions=["See timvisher_browser's error above", "Or pass the target's URL or file explicitly"])


def _tracked(path, db):
    if db is None:
        return None
    rows = db.execute("SELECT o.id, o.url FROM authored a JOIN objects o ON o.id = a.object_id WHERE a.path = ?",
                      (str(path.absolute()),)).fetchall()
    if not rows:
        store = state_db.root().resolve()
        real = path.resolve()
        if real.is_relative_to(store):
            relative = real.relative_to(store)
            candidates = [relative, relative.parent]
            for candidate in candidates:
                rows = db.execute("SELECT id, url FROM objects WHERE store_path = ?", (str(candidate),)).fetchall()
                if rows:
                    break
            if not rows:
                rows = _by_export(real if real.is_dir() else real.parent, db)
    if rows:
        return rows[0]
    return None


def _by_export(directory, db):
    for export in sorted(directory.glob("*.json")):
        try:
            object_id = json.loads(export.read_text(encoding="utf-8")).get("id")
        except (ValueError, AttributeError):
            continue
        rows = db.execute("SELECT id, url FROM objects WHERE id = ?", (object_id,)).fetchall()
        if rows:
            return rows
    return []


def _legacy_url(path):
    beside = path.with_name(path.name + ".url")
    if beside.is_file():
        return beside.read_text(encoding="utf-8").strip()
    return None


def _from_file(path, noun, db, creating):
    tracked = _tracked(path, db)
    if tracked is not None:
        object_id, url = tracked
        return dataclasses.replace(parse_url(url, noun), object_id=object_id, via="tracked")
    legacy = _legacy_url(path)
    if legacy is not None:
        return dataclasses.replace(parse_url(legacy, noun, f" (from {path}.url)"), via="legacy")
    if not creating:
        fail("timvisher_gh_target_untracked", f"'{path}' isn't tracked, and this command doesn't create anything.",
             status=USAGE, reason="An untracked file is a source only for commands that create something.",
             suggestions=["Create it with the bare sync or 'push'",
                          "Or pass the URL of the object it belongs to"])
    return Target("source", source=path, via="untracked")


def _git(*args, cwd):
    return subprocess.run(["git", *args], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          text=True).stdout.strip()


def _context_pr(context, db, noun):
    branch = _git("rev-parse", "--abbrev-ref", "HEAD", cwd=context.toplevel)
    if not branch or branch == "HEAD":
        return None
    owner, repo = context.spec.split("/")
    if db is not None:
        row = db.execute("SELECT o.id, o.url FROM context c JOIN objects o ON o.id = c.pr_id "
                         "WHERE c.worktree = ? AND c.owner = ? AND c.repo = ? AND c.branch = ?",
                         (context.toplevel, owner, repo, branch)).fetchone()
        if row is not None:
            return dataclasses.replace(parse_url(row[1], noun), object_id=row[0], via="context")
    done = subprocess.run(["gh", "-R", context.spec, "pr", "list", "--head", branch, "--state", "all",
                           "--json", "number,state"], stdout=subprocess.PIPE, text=True)
    if done.returncode != 0:
        fail("timvisher_gh_gh_failed", f"Unable to look up the PR for branch '{branch}' in {context.spec}.",
             suggestions=["Check gh's error above, then retry", "Or pass the PR's URL"])
    pulls = json.loads(done.stdout or "[]")
    if not pulls:
        return None
    # An open PR wins over closed ones for the same branch name, then the
    # newest: branch names get reused after a merge.
    chosen = max(pulls, key=lambda p: (p["state"] == "OPEN", p["number"]))
    return Target("pr", owner=owner, repo=repo, number=chosen["number"], via="context")


def _nothing(noun, context):
    suggestions = [f"Pass the {noun}'s URL or file", f"Or '{BROWSER_TAB}' to use the browser's active tab"]
    if noun in ("pr", "issue"):
        suggestions.insert(1, f"Or write {context.toplevel}/{noun}.md to create one")
    fail("timvisher_gh_target_none", f"No {noun} target: none was given and the worktree context has none.",
         suggestions=suggestions)


def resolve(noun, argument, *, context, db=None, creating=False):
    if argument == BROWSER_TAB:
        return dataclasses.replace(parse_url(_browser_url(), noun, " (the current browser tab)"), via="browser")
    if argument is not None:
        if re.match(r"https?://", argument):
            return parse_url(argument, noun)
        path = pathlib.Path(argument)
        if path.is_file():
            return _from_file(path, noun, db, creating)
        if path.is_dir() and (tracked := _tracked(path, db)) is not None:
            object_id, url = tracked
            return dataclasses.replace(parse_url(url, noun), object_id=object_id, via="tracked")
        fail("timvisher_gh_target_invalid", f"'{argument}' is neither a target URL nor a file.", status=USAGE,
             suggestions=[f"Pass a file, '{BROWSER_TAB}', or one of: {shape}" for shape in SHAPES])

    if noun in ("comment", "thread"):
        found = _context_pr(context, db, noun)
        if found is None:
            _nothing("PR", context)
        return found

    # The worktree context names a PR, so it is never an issue's target.
    if noun == "pr":
        found = _context_pr(context, db, noun)
        if found is not None:
            return found
    root_source = pathlib.Path(context.toplevel) / f"{noun}.md"
    if os.path.lexists(root_source):
        tracked = _tracked(root_source, db)
        if tracked is not None or _legacy_url(root_source) is not None or creating:
            return _from_file(root_source, noun, db, creating)
    try:
        found = _match(browser.active_tab()["url"], noun)
    except subprocess.CalledProcessError:
        found = None
    if found is not None and noun == "pr" and found.kind in ("comment", "review_comment"):
        found = Target("pr", owner=found.owner, repo=found.repo, number=found.number)
    if found is None or found.kind != noun:
        _nothing(noun, context)
    aictl.info(code="timvisher_gh_target_from_browser_tab",
               message=f"Using the current browser tab's {found.url} as the {noun} target.",
               reason="No target was given, the worktree context has none, "
                      f"and {context.toplevel} has no {noun}.md.")
    return dataclasses.replace(found, via="browser")
