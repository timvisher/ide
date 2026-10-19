import json
import pathlib
import subprocess
import unittest

from support.case import GhTestCase
from support.remotes import git

SHIM = pathlib.Path(__file__).resolve().parents[2] / "bash" / "bin" / "gh"
REPO = "testuser/testrepo"


class RealShimTest(GhTestCase):
    def setUp(self):
        super().setUp()
        prefix = self.tmp / "brew-prefix"
        (prefix / "bin").mkdir(parents=True)
        (self.github.bin / "gh").rename(prefix / "bin" / "gh")
        (self.github.bin / "gh").symlink_to(SHIM)
        brew = self.github.bin / "brew"
        brew.write_text(f"#!/usr/bin/env bash\n[[ $1 == --prefix ]] && echo '{prefix}'\n")
        brew.chmod(0o755)
        self.config = self.tmp / "config"
        (self.config / "orgs" / "testuser").mkdir(parents=True)
        (self.config / "orgs" / "testuser" / "account").write_text("tester\n")
        self.github.respond(["auth", "token"], stdout="token-for-tester\n")
        self.github.respond(["pr", "list"], stdout="[]")
        git("checkout", "-q", "-b", "feature", cwd=self.work)
        git("commit", "-q", "--allow-empty", "-m", "work", cwd=self.work)

    def test_a_pr_push_goes_through_the_real_shim_with_the_repos_account(self):
        (self.work / "pr.md").write_text("Title\n\nBody\n")
        rc, out, err = self.run_gh("pr", "push", TIMVISHER_AGENT="1", TIMVISHER_GH_CONFIG_DIR=str(self.config))
        self.assertEqual((0, f"https://github.com/{REPO}/pull/1\n"), (rc, out), err)
        calls = [c for c in self.github.calls if c["argv"][:2] != ["auth", "token"]]
        self.assertTrue(calls)
        self.assertEqual({"token-for-tester"}, {c["gh_token"] for c in calls})
        self.assertIn("POST", {c.get("method") for c in calls})
        self.assertEqual("Title", self.github.state["pulls"][REPO]["1"]["title"])

    def test_the_same_write_outside_timvisher_gh_is_blocked(self):
        done = subprocess.run(["gh", "-R", REPO, "api", "-X", "POST", f"repos/{REPO}/pulls", "-f", "title=x"],
                              cwd=self.work, env=self.env(TIMVISHER_AGENT="1",
                                                          TIMVISHER_GH_CONFIG_DIR=str(self.config)),
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertNotEqual(0, done.returncode)
        codes = [json.loads(line)["code"] for line in done.stderr.splitlines() if line.startswith("{")]
        self.assertIn("gh_api_mutation_blocked", codes)
        self.assertEqual({}, self.github.state["pulls"])


if __name__ == "__main__":
    unittest.main()
