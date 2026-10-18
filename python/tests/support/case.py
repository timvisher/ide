import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

from support.github import FakeGitHub
from support.remotes import REAL_GIT, bare_remote, worktree
from timvisher.testing import fresh_home

TIMVISHER_GH = pathlib.Path(__file__).resolve().parents[2] / "bin" / "timvisher_gh"


class GhTestCase(unittest.TestCase):
    repo = "testuser/testrepo"

    def setUp(self):
        home = fresh_home()
        self.home = pathlib.Path(home.__enter__())
        self.addCleanup(home.__exit__, None, None, None)

        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = pathlib.Path(tmp.name)

        self.github = FakeGitHub(self.tmp / "github")
        self.github.add_repo(self.repo)
        (self.github.bin / "git").symlink_to(REAL_GIT)

        self.remote = bare_remote(self.tmp, self.repo)
        self.work = worktree(self.tmp, self.remote)

    def env(self, **extra):
        return {**os.environ, **self.github.env(),
                "PATH": f"{self.github.bin}:{os.environ['PATH']}", **extra}

    def run_gh(self, *args, cwd=None, stdin=None, **env):
        done = subprocess.run([sys.executable, str(TIMVISHER_GH), *args], cwd=cwd or self.work,
                              env=self.env(**env), input=stdin,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return done.returncode, done.stdout, done.stderr

    def gh(self, *args, cwd=None, stdin=None):
        done = subprocess.run(["gh", *args], cwd=cwd or self.work, env=self.env(), input=stdin,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return done.returncode, done.stdout, done.stderr
