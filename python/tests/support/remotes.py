import os
import pathlib
import subprocess

REAL_GIT = next(g for g in ("/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git") if os.access(g, os.X_OK))

IDENTITY = {"GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com"}


def git(*args, cwd):
    done = subprocess.run([REAL_GIT, *args], cwd=cwd, env={**os.environ, **IDENTITY},
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if done.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} failed in {cwd}: {done.stderr}")
    return done.stdout.strip()


# A path whose last parts read github.com:OWNER/REPO, rather than an
# insteadOf rewrite of a github.com URL, because 'git remote get-url'
# expands insteadOf and timvisher_gh reads OWNER/REPO from that URL. The
# leading slash keeps git treating it as a local path, not ssh.
def bare_remote(root, repo="testuser/testrepo"):
    owner, name = repo.split("/")
    path = pathlib.Path(root) / "remotes" / f"github.com:{owner}" / f"{name}.git"
    path.mkdir(parents=True)
    git("init", "-q", "--bare", "--initial-branch=main", cwd=path)
    return path


def worktree(root, remote, *, name="work", branch="main"):
    path = pathlib.Path(root) / name
    path.mkdir(parents=True)
    git("init", "-q", "--initial-branch=main", cwd=path)
    git("remote", "add", "origin", str(remote), cwd=path)
    git("commit", "-q", "--allow-empty", "-m", "init", cwd=path)
    git("push", "-q", "-u", "origin", "HEAD:refs/heads/main", cwd=path)
    if branch != "main":
        git("checkout", "-q", "-b", branch, cwd=path)
        git("push", "-q", "-u", "origin", f"HEAD:refs/heads/{branch}", cwd=path)
    return path


def commit_on_remote(root, remote, branch, message, *, name="other"):
    path = pathlib.Path(root) / name
    if not path.exists():
        git("clone", "-q", str(remote), str(path), cwd=root)
    git("fetch", "-q", "origin", cwd=path)
    git("checkout", "-q", "-B", branch, f"origin/{branch}", cwd=path)
    git("commit", "-q", "--allow-empty", "-m", message, cwd=path)
    git("push", "-q", "origin", f"HEAD:refs/heads/{branch}", cwd=path)
    return git("rev-parse", "HEAD", cwd=path)
