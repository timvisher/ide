import dataclasses
import os
import re
import subprocess

from timvisher.gh.errors import fail, usage

_SPEC = re.compile(r"[^/]+/[^/]+")


@dataclasses.dataclass(frozen=True)
class Context:
    spec: str
    toplevel: str | None = None


def spec_from_url(url):
    url = url.removesuffix(".git")
    if "://" in url:
        url = url.split("://", 1)[1]
        url = url.split("/", 1)[1] if "/" in url else ""
    elif ":" in url:
        url = url.split(":", 1)[1]
    return url


def from_option(value):
    spec = value.removeprefix("github.com/")
    if not _SPEC.fullmatch(spec):
        usage(f"Option -R: '{value}' is not OWNER/REPO (or github.com/OWNER/REPO)")
    return Context(spec=spec)


def _git(*args, cwd):
    return subprocess.run(["git", *args], cwd=cwd, stdout=subprocess.PIPE, text=True)


def _target_remote(toplevel):
    remotes = _git("remote", cwd=toplevel).stdout.split()
    branch = _git("rev-parse", "--abbrev-ref", "HEAD", cwd=toplevel).stdout.strip()
    tracking = _git("config", f"branch.{branch}.remote", cwd=toplevel).stdout.strip()
    if tracking and tracking in remotes:
        return tracking
    if "upstream" in remotes:
        return "upstream"
    return "origin"


def from_worktree(path):
    if path is not None and not os.path.isdir(path):
        fail("timvisher_gh_no_such_path", f"Option -C: unable to enter '{path}'",
             suggestions=["Pass -C a worktree directory that exists"])
    shown = _git("rev-parse", "--show-toplevel", cwd=path or ".")
    if shown.returncode != 0:
        fail("timvisher_gh_not_a_repo", "Not in a git repository",
             suggestions=["Run timvisher_gh inside a worktree, or pass -C <worktree>",
                          "For a repository with no worktree, use 'timvisher_gh -R OWNER/REPO info <field>'"])
    toplevel = shown.stdout.strip()
    remote = _target_remote(toplevel)
    url = _git("remote", "get-url", remote, cwd=toplevel).stdout.strip()
    spec = spec_from_url(url)
    if not spec:
        fail("timvisher_gh_no_repo_spec", f"Could not determine repository spec for remote '{remote}'",
             suggestions=[f"Check 'git -C {toplevel} remote get-url {remote}'"])
    return Context(spec=spec, toplevel=toplevel)
