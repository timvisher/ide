import os
import pathlib
import subprocess
import sys

from timvisher import aictl, logging
from timvisher.gh.errors import fail

CORE = pathlib.Path(__file__).resolve().parents[3] / "bin" / "timvisher_gh.config"


def roots():
    core = pathlib.Path(os.environ.get("TIMVISHER_GH_CORE_CONFIG_DIR") or CORE)
    ext = pathlib.Path(os.environ.get("TIMVISHER_GH_CONFIG_DIR")
                       or pathlib.Path.home() / ".config/timvisher/ide/python/bin/timvisher_gh.config")
    return [core] if ext == core else [core, ext]


def _executables(directory):
    if not directory.is_dir():
        return []
    return [path for path in sorted(directory.iterdir())
            if path.is_file() and os.access(path, os.X_OK) and not path.name.startswith(".")
            and not path.name.endswith("~")]


class Hooks:
    def __init__(self, *, repo, worktree, pr_url=None, title=None, state_dir=None, open_=False,
                 merge_commit=None):
        self.repo = repo
        self.worktree = worktree
        self.pr_url = pr_url
        self.title = title
        self.state_dir = state_dir
        self.open = open_
        self.merge_commit = merge_commit
        self._changed = None

    def changed(self):
        if self._changed is None:
            if self.pr_url:
                done = subprocess.run(["gh", "-R", self.repo, "pr", "diff", self.pr_url, "--name-only"],
                                      stdout=subprocess.PIPE, text=True)
                self._changed = done.stdout.splitlines() if done.returncode == 0 else []
            else:
                base = subprocess.run(["gh", "-R", self.repo, "repo", "view", self.repo, "--json",
                                       "defaultBranchRef", "--jq", ".defaultBranchRef.name"],
                                      stdout=subprocess.PIPE, text=True).stdout.strip()
                if not base:
                    fail("timvisher_gh_hooks_no_default_branch",
                         f"Could not determine the default branch of {self.repo} for path-scoped hooks.",
                         suggestions=["Check gh's error above, then rerun"])
                merge_base = subprocess.run(["git", "merge-base", f"refs/remotes/origin/{base}", "HEAD"],
                                            cwd=self.worktree, stdout=subprocess.PIPE, text=True).stdout.strip()
                if not merge_base:
                    fail("timvisher_gh_hooks_no_merge_base",
                         f"Couldn't find the merge base of HEAD and origin/{base} for path-scoped hooks.",
                         suggestions=[f"Fetch it: 'git fetch origin {base}', then rerun"])
                done = subprocess.run(["git", "diff", "--name-only", merge_base, "HEAD"], cwd=self.worktree,
                                      stdout=subprocess.PIPE, text=True)
                self._changed = done.stdout.splitlines() if done.returncode == 0 else []
        return self._changed

    def _touches(self, scope):
        prefix = scope.rstrip("/") + "/"
        return any(path.startswith(prefix) for path in self.changed())

    def collect(self, phase, when):
        owner = self.repo.split("/")[0]
        found = []
        for root in roots():
            found += [(hook, "") for hook in _executables(root / "orgs" / owner / "pr" / phase / f"{when}.d")]
            found += [(hook, "") for hook in _executables(root / "repos" / self.repo / "pr" / phase / f"{when}.d")]
            paths = root / "repos" / self.repo / "paths"
            if paths.is_dir():
                for directory in sorted(paths.rglob(f"pr/{phase}/{when}.d")):
                    scope = str(directory.relative_to(paths).parent.parent.parent)
                    if self._touches(scope):
                        found += [(hook, scope) for hook in _executables(directory)]
        return found

    def _env(self, phase, when, scope):
        number = self.pr_url.rsplit("/", 1)[-1] if self.pr_url and "/pull/" in self.pr_url else ""
        head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=self.worktree, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, text=True).stdout.strip()
        current = self.title() if callable(self.title) else self.title
        title = self.repo + (f"#{number}" if number else "") + (f": {current}" if current else "")
        return {**os.environ, "TIMVISHER_GH_PHASE": phase, "TIMVISHER_GH_HOOK": when,
                "TIMVISHER_GH_REPO": self.repo, "TIMVISHER_GH_PR_URL": self.pr_url or "",
                "TIMVISHER_GH_PR_NUMBER": number, "TIMVISHER_GH_HEAD_SHA": head,
                "TIMVISHER_GH_WORKTREE": str(self.worktree), "TIMVISHER_GH_STATE_DIR": str(self.state_dir or ""),
                "TIMVISHER_GH_MERGE_COMMIT": self.merge_commit or "", "TIMVISHER_GH_NOTIFY_TITLE": title,
                "TIMVISHER_GH_OPEN": "true" if self.open else "false", "TIMVISHER_GH_PATH_SCOPE": scope}

    def run(self, phase, when):
        failures = 0
        for hook, scope in self.collect(phase, when):
            logging.info("Running %s %s-hook %s", phase, when, hook)
            done = subprocess.run([str(hook)], cwd=self.worktree, env=self._env(phase, when, scope),
                                  stdout=sys.stderr, stderr=sys.stderr)
            if done.returncode != 0:
                logging.error("%s %s-hook failed: %s", phase, when, hook)
                failures += 1
                if when == "pre":
                    break
        return failures == 0

    def pre(self, phase):
        if not self.run(phase, "pre"):
            aictl.error(code="timvisher_gh_pre_hook_failed",
                        message=f"A {phase} pre-hook failed; not proceeding.",
                        suggestions=["Fix what the hook reported, then rerun"])
            return False
        return True

    def post(self, phase):
        if not self.run(phase, "post"):
            aictl.error(code="timvisher_gh_post_hook_failed",
                        message=f"{phase} post-hook(s) failed; the rest ran.",
                        suggestions=["Fix what failed, then rerun; completed steps report 'already'"])
            return False
        return True
