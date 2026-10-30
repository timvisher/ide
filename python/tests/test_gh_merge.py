import json
import os
import pathlib
import time
import unittest

from support.case import GhTestCase
from support.remotes import git

REPO = "testuser/testrepo"
PR = f"https://github.com/{REPO}/pull/7"

HOOK = """#!/usr/bin/env bash
printf '%s %s %s\\n' "${0##*/}" "$TIMVISHER_GH_PHASE" "$TIMVISHER_GH_HOOK" >> "$HOOK_LOG"
exit {rc}
"""


class MergeTest(GhTestCase):
    def setUp(self):
        super().setUp()
        git("checkout", "-q", "-b", "feature", cwd=self.work)
        self.github.add_pull(REPO, 7, head="feature", title="T")
        self.github.respond(["pr", "list"], stdout=json.dumps([{"number": 7, "state": "OPEN"}]))
        self.core = self.tmp / "core-config"
        self.log = self.tmp / "hooks.log"
        self.log.touch()

    def merge(self, *args, stdin="", cwd=None, **env):
        rc, out, err = self.run_gh_as_tim("pr", "merge", *args, cwd=cwd, stdin=stdin,
                                   TIMVISHER_GH_PR_MERGE_POLL_INTERVAL="0", HOOK_LOG=str(self.log),
                                   TIMVISHER_GH_CORE_CONFIG_DIR=str(self.core),
                                   TIMVISHER_GH_CONFIG_DIR=str(self.tmp / "no-ext"), **env)
        self.err = err
        return rc, out

    def codes(self):
        return [json.loads(line)["code"] for line in self.err.splitlines() if line.startswith('{"type":"instruction"')]

    def pull(self):
        return self.github.state["pulls"][REPO]["7"]

    def attempts(self):
        return self.pull().get("merge_attempts", [])

    # The fresh HOME's .config/timvisher/ide links to the real system-extensions
    # worktree, so the link is swapped for a directory of this test's own
    # before anything is written there.
    def comment_repos(self, *repos):
        ide = self.home / ".config/timvisher/ide"
        if ide.is_symlink():
            ide.unlink()
        ide.mkdir(parents=True, exist_ok=True)
        (ide / "gh-pr-merge-comment-repos").write_text("".join(f"{repo}\n" for repo in repos))

    def merge_comments(self):
        return [c for c in self.github.state["issue_comments"].values() if c["body"] == "/merge"]

    def hook(self, relative, rc=0):
        path = self.core / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(HOOK.replace("{rc}", str(rc)))
        path.chmod(0o755)

    def state_of(self):
        return self.run_gh("pr", "info", PR, ".state")[1].strip()

    def test_an_open_pr_merges_waits_and_records_the_merge(self):
        rc, out = self.merge(PR, stdin="y\n")
        self.assertEqual((0, f"{PR}\n"), (rc, out), self.err)
        self.assertEqual(["merge"], [a["strategy"] for a in self.attempts()])
        self.assertEqual(PR, self.attempts()[0]["args"][-1])
        self.assertEqual("merged", self.state_of())
        self.assertIn("timvisher_gh_pr_merged", self.codes())

    def test_an_omitted_target_is_the_worktrees_pr(self):
        self.assertEqual(0, self.merge(stdin="y\n")[0], self.err)
        self.assertTrue(self.pull()["merged"])

    def test_already_merged_reports_it_without_prompting_and_records_it(self):
        self.github.update_pull(REPO, 7, merged=True, state="closed", merge_commit_sha="a" * 40)
        for _ in range(2):
            rc, _ = self.merge(PR)
            self.assertEqual(0, rc, self.err)
            self.assertIn("timvisher_gh_pr_already_merged", self.codes())
        self.assertEqual([], self.attempts())
        self.assertEqual("merged", self.state_of())

    def test_strategies_come_from_the_prs_repo(self):
        self.github.add_repo(REPO, merge=False, squash=True)
        self.assertEqual(0, self.merge(PR, stdin="y\n")[0], self.err)
        self.assertEqual(["squash"], [a["strategy"] for a in self.attempts()])

    def test_a_failed_strategy_offers_the_next(self):
        self.github.add_repo(REPO, merge=True, squash=True)
        self.github.update_pull(REPO, 7, merge_fail=["merge"])
        self.assertEqual(0, self.merge(PR, stdin="y\n\n")[0], self.err)
        self.assertEqual(["merge", "squash"], [a["strategy"] for a in self.attempts()])
        self.github.update_pull(REPO, 7, merged=False, state="open", merge_attempts=[])
        rc, _ = self.merge(PR, stdin="y\nn\n")
        self.assertEqual((1, ["merge"]), (rc, [a["strategy"] for a in self.attempts()]))

    def test_gh_merge_args_go_after_dash_dash(self):
        self.assertEqual(0, self.merge(PR, "--", "--delete-branch", stdin="y\n")[0], self.err)
        self.assertIn("--delete-branch", self.attempts()[0]["args"])

    def test_declining_the_prompt_exits_nonzero_without_merging(self):
        rc, _ = self.merge(PR, stdin="n\n")
        self.assertEqual((1, []), (rc, self.attempts()))
        self.assertIn("timvisher_gh_merge_declined", self.codes())

    def test_a_closed_pr_fails_without_merging(self):
        self.github.update_pull(REPO, 7, state="closed")
        rc, _ = self.merge(PR, stdin="y\n")
        self.assertEqual((1, ["timvisher_gh_pr_closed"], []), (rc, self.codes(), self.attempts()))

    def test_auto_merge_or_the_merge_queue_skips_straight_to_waiting(self):
        for flag in ("auto_merge", "in_merge_queue"):
            self.github.update_pull(REPO, 7, **{flag: True})
            rc, _ = self.merge(PR, TIMVISHER_GH_PR_MERGE_TIMEOUT="0")
            self.assertEqual(1, rc, flag)
            self.assertEqual(["timvisher_gh_merge_requested", "timvisher_gh_merge_timeout"],
                             [c for c in self.codes() if c.startswith("timvisher_gh_merge")])
            self.assertEqual([], self.attempts())
            self.github.update_pull(REPO, 7, **{flag: False})

    def test_the_comment_repos_config_matches_case_insensitively(self):
        self.comment_repos("TestUser/TestRepo")
        self.assertEqual(1, self.merge(PR, stdin="y\n", TIMVISHER_GH_PR_MERGE_TIMEOUT="0")[0])
        self.assertEqual((1, []), (len(self.merge_comments()), self.attempts()))

    def test_an_unlisted_repo_merges_with_gh(self):
        self.comment_repos("someone/else")
        self.assertEqual(0, self.merge(PR, stdin="y\n")[0], self.err)
        self.assertEqual(([], ["merge"]), (self.merge_comments(), [a["strategy"] for a in self.attempts()]))

    def test_a_comment_repo_doesnt_post_a_duplicate_merge(self):
        self.comment_repos(REPO)
        self.github.update_pull(REPO, 7, last_commit_at="2026-10-10T09:00:00Z")
        self.github.add_issue_comment(REPO, 7, "/merge")
        rc, _ = self.merge(PR, TIMVISHER_GH_PR_MERGE_TIMEOUT="0")
        self.assertEqual(1, rc)
        self.assertIn("timvisher_gh_merge_requested", self.codes())
        self.assertEqual(1, len(self.merge_comments()))

    def test_a_comment_repo_re_requests_when_merge_predates_the_last_push(self):
        self.comment_repos(REPO)
        self.github.add_issue_comment(REPO, 7, "/merge")
        self.github.update_pull(REPO, 7, last_commit_at="2026-10-10T11:00:00Z")
        self.merge(PR, stdin="y\n", TIMVISHER_GH_PR_MERGE_TIMEOUT="0")
        self.assertEqual(2, len(self.merge_comments()))

    def test_a_comment_repo_ignores_another_users_merge(self):
        self.comment_repos(REPO)
        self.github.update_pull(REPO, 7, last_commit_at="2026-10-10T09:00:00Z")
        self.github.add_issue_comment(REPO, 7, "/merge", user="alice")
        self.merge(PR, stdin="y\n", TIMVISHER_GH_PR_MERGE_TIMEOUT="0")
        self.assertEqual(2, len(self.merge_comments()))

    def test_a_gh_merge_repo_merges_even_after_a_merge_comment(self):
        self.github.add_issue_comment(REPO, 7, "/merge")
        self.assertEqual(0, self.merge(PR, stdin="y\n")[0], self.err)
        self.assertEqual(["merge"], [a["strategy"] for a in self.attempts()])

    def test_merge_pre_hooks_gate_a_request_and_are_skipped_once_merged(self):
        self.hook("orgs/testuser/pr/merge/pre.d/10-gate")
        self.assertEqual(0, self.merge(PR, stdin="y\n")[0], self.err)
        self.assertEqual(["10-gate merge pre"], self.log.read_text().splitlines())
        self.merge(PR)
        self.assertEqual(1, len(self.log.read_text().splitlines()))

    def test_a_failing_merge_pre_hook_blocks_the_request(self):
        self.hook("orgs/testuser/pr/merge/pre.d/10-gate", rc=1)
        rc, _ = self.merge(PR, stdin="y\n")
        self.assertEqual((1, []), (rc, self.attempts()))

    def test_no_pr_is_an_error(self):
        self.github._update(lambda s: s["responses"].clear())
        self.github.respond(["pr", "list"], stdout="[]")
        (self.work / "pr.md").write_text("T\n")
        rc, _ = self.merge()
        self.assertEqual((1, ["timvisher_gh_pr_missing"]), (rc, self.codes()))

    def test_the_trunk_worktree_is_pulled_in_the_background(self):
        git_home = pathlib.Path(os.environ["TIMVISHER_GIT_HOME"])
        feature = git_home / "testuser" / "testrepo" / "feature"
        trunk = git_home / "testuser" / "testrepo" / "main"
        feature.parent.mkdir(parents=True)
        git("clone", "-q", str(self.remote), str(feature), cwd=self.tmp)
        git("checkout", "-q", "-b", "feature", cwd=feature)
        git("clone", "-q", str(self.remote), str(trunk), cwd=self.tmp)
        self.assertEqual(0, self.merge(PR, stdin="y\n", cwd=feature)[0], self.err)
        log = trunk / ".timvisher_gh" / "trunk-pull.log"
        for _ in range(100):
            if log.exists() and "git pull --ff-only after" in log.read_text():
                break
            time.sleep(0.05)
        self.assertIn(f"git pull --ff-only after {PR}", log.read_text())


if __name__ == "__main__":
    unittest.main()
