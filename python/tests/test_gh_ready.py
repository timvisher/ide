import json
import unittest

from support.case import GhTestCase
from support.remotes import git

REPO = "testuser/testrepo"
PR = f"https://github.com/{REPO}/pull/7"

HOOK = """#!/usr/bin/env bash
printf '%s %s %s\\n' "${0##*/}" "$TIMVISHER_GH_PHASE" "$TIMVISHER_GH_HOOK" >> "$HOOK_LOG"
exit {rc}
"""


class ReadyTest(GhTestCase):
    def setUp(self):
        super().setUp()
        git("checkout", "-q", "-b", "feature", cwd=self.work)
        self.github.add_pull(REPO, 7, head="feature", title="T", draft=True)
        self.github.respond(["pr", "list"], stdout=json.dumps([{"number": 7, "state": "OPEN"}]))
        self.core = self.tmp / "core-config"
        self.ext = self.tmp / "ext-config"
        self.log = self.tmp / "hooks.log"
        self.log.touch()

    def checks(self, *rounds):
        for checks in rounds:
            body = checks if isinstance(checks, str) else json.dumps(
                [{"name": name, "bucket": bucket} for name, bucket in checks])
            self.github.respond(["pr", "checks"], stdout=body, once=True)

    def ready(self, *args, **env):
        rc, out, err = self.run_gh("pr", "ready", *args, TIMVISHER_AGENT="1", TIMVISHER_GH_PR_READY_POLL_INTERVAL="0",
                                   HOOK_LOG=str(self.log), TIMVISHER_GH_CORE_CONFIG_DIR=str(self.core),
                                   TIMVISHER_GH_CONFIG_DIR=str(self.ext), **env)
        self.err = err
        return rc, out

    def codes(self):
        return [json.loads(line)["code"] for line in self.err.splitlines() if line.startswith('{"type":"instruction"')]

    def draft(self):
        return self.github.state["pulls"][REPO]["7"]["draft"]

    def hook(self, root, relative, rc=0):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(HOOK.replace("{rc}", str(rc)))
        path.chmod(0o755)

    def exclude(self, root, relative, text):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def test_marks_the_pr_ready_when_all_checks_pass(self):
        self.checks([("build", "pass"), ("lint", "pass")])
        self.assertEqual((0, f"{PR}\n"), self.ready(PR), self.err)
        self.assertFalse(self.draft())

    def test_waits_through_pending_checks(self):
        self.checks([("build", "pending")], [("build", "pending")], [("build", "pass")])
        self.assertEqual(0, self.ready(PR)[0], self.err)
        self.assertFalse(self.draft())
        self.assertEqual(3, sum(c["argv"][2:4] == ["pr", "checks"] for c in self.github.calls))

    def test_failed_checks_stop_without_marking_ready(self):
        self.checks([("build", "fail"), ("lint", "pass")])
        rc, _ = self.ready(PR)
        self.assertEqual((1, ["timvisher_gh_checks_failed"]), (rc, self.codes()))
        self.assertTrue(self.draft())
        self.assertIn("build", self.err)

    def test_already_ready_skips_checks_and_pre_hooks_and_runs_post_hooks(self):
        self.github._update(lambda s: s["pulls"][REPO]["7"].update(draft=False))
        self.hook(self.core, "orgs/testuser/pr/ready/pre.d/10-gate")
        self.hook(self.core, "orgs/testuser/pr/ready/post.d/10-after")
        self.assertEqual(0, self.ready(PR)[0], self.err)
        self.assertEqual(["10-after ready post"], self.log.read_text().splitlines())
        self.assertEqual(0, sum(c["argv"][2:4] == ["pr", "checks"] for c in self.github.calls))
        self.assertIn("timvisher_gh_pr_already_ready", self.codes())

    def test_ready_runs_pre_hooks_then_marks_ready_then_post_hooks(self):
        self.checks([("build", "pass")])
        self.hook(self.core, "orgs/testuser/pr/ready/pre.d/10-gate")
        self.hook(self.core, "orgs/testuser/pr/ready/post.d/10-after")
        self.assertEqual(0, self.ready(PR)[0], self.err)
        self.assertEqual(["10-gate ready pre", "10-after ready post"], self.log.read_text().splitlines())
        self.assertFalse(self.draft())

    def test_a_failing_pre_hook_keeps_the_pr_a_draft(self):
        self.checks([("build", "pass")])
        self.hook(self.core, "orgs/testuser/pr/ready/pre.d/10-gate", rc=1)
        rc, _ = self.ready(PR)
        self.assertNotEqual(0, rc)
        self.assertTrue(self.draft())

    def test_org_and_repo_exclude_patterns_from_both_roots_ignore_checks(self):
        self.exclude(self.core, "orgs/testuser/pr/ready/exclude-checks.txt", "# meta checks\n\nmergegate\n")
        self.exclude(self.ext, "repos/testuser/testrepo/pr/ready/exclude-checks.txt", "  ^flaky-.*  \n")
        self.checks([("build", "pass"), ("mergegate", "pending"), ("flaky-e2e", "fail")])
        self.assertEqual(0, self.ready(PR)[0], self.err)
        self.assertFalse(self.draft())

    def test_all_checks_excluded_proceeds_immediately(self):
        self.exclude(self.ext, "orgs/testuser/pr/ready/exclude-checks.txt", ".*\n")
        self.checks([("mergegate", "pending")])
        self.assertEqual(0, self.ready(PR)[0], self.err)

    def test_an_invalid_exclude_pattern_stops_instead_of_passing_failing_checks(self):
        self.exclude(self.ext, "repos/testuser/testrepo/pr/ready/exclude-checks.txt", "(\n")
        self.checks([("build", "fail")])
        rc, _ = self.ready(PR)
        self.assertEqual((1, ["timvisher_gh_bad_exclude_pattern"]), (rc, self.codes()))
        self.assertTrue(self.draft())

    def checks_calls(self):
        return sum(c["argv"][2:4] == ["pr", "checks"] for c in self.github.calls)

    def test_a_pr_with_no_checks_past_the_grace_period_is_marked_ready(self):
        self.github.respond(["pr", "checks"], stdout="", stderr="no checks reported on the 'feature' branch\n", status=1)
        rc, _ = self.ready(PR, TIMVISHER_GH_PR_READY_NO_CHECKS_GRACE="0")
        self.assertEqual(0, rc, self.err)
        self.assertIn("timvisher_gh_checks_none", self.codes())
        self.assertFalse(self.draft())
        self.assertEqual(1, self.checks_calls())

    def test_no_checks_within_the_grace_period_keeps_waiting(self):
        self.github.respond(["pr", "checks"], stdout="", stderr="no checks reported\n", status=1, once=True)
        self.checks([("build", "pass")])
        self.assertEqual(0, self.ready(PR)[0], self.err)
        self.assertNotIn("timvisher_gh_checks_none", self.codes())
        self.assertEqual(2, self.checks_calls())

    def test_other_gh_errors_never_count_as_no_checks(self):
        self.github.respond(["pr", "checks"], stdout="", stderr="HTTP 502\n", status=1, once=True)
        self.checks([("build", "pass")])
        self.assertEqual(0, self.ready(PR, TIMVISHER_GH_PR_READY_NO_CHECKS_GRACE="0")[0], self.err)
        self.assertNotIn("timvisher_gh_checks_none", self.codes())
        self.assertEqual(2, self.checks_calls())

    def test_recovers_from_non_json_and_ordinary_gh_errors(self):
        self.github.respond(["pr", "checks"], stdout="", stderr="no checks reported\n", status=1, once=True)
        self.checks("not json", [("build", "pass")])
        self.assertEqual(0, self.ready(PR)[0], self.err)
        self.assertIn("no checks reported", self.err)
        self.assertFalse(self.draft())

    def test_stops_when_gh_refuses_instead_of_retrying_forever_with_or_without_an_agent(self):
        refusal = json.dumps({"type": "instruction", "level": "error", "code": "gh_account_token_unavailable",
                              "message": "no token"})
        self.github.respond(["pr", "checks"], stderr="ERROR gh_account_token_unavailable: no token\n", status=1,
                            aictl=refusal + "\n")
        outer = self.tmp / "outer.jsonl"
        outer.touch()
        for agent in ("1", ""):
            mark = len(self.github.calls)
            rc, _, err = self.run_gh("pr", "ready", PR, TIMVISHER_AGENT=agent, TIMVISHER_GH_PR_READY_POLL_INTERVAL="0",
                                     TIMVISHER_AICTL_LOG=str(outer))
            self.assertEqual(1, rc, agent)
            self.assertIn("timvisher_gh_checks_refused", err)
            self.assertEqual(1, sum(c["argv"][2:4] == ["pr", "checks"] for c in self.github.calls[mark:]))
        self.assertIn("gh_account_token_unavailable", outer.read_text())

    def test_already_ready_records_it_so_a_later_push_doesnt_refuse(self):
        self.github._update(lambda s: s["pulls"][REPO]["7"].update(draft=False))
        self.assertEqual(0, self.ready(PR)[0], self.err)
        rc, out, err = self.run_gh("pr", "info", PR, '.posted["source.draft"]')
        self.assertEqual((0, "false\n"), (rc, out), err)

    def test_no_pr_is_an_error(self):
        self.github._update(lambda s: s["responses"].clear())
        self.github.respond(["pr", "list"], stdout="[]")
        (self.work / "pr.md").write_text("T\n")
        rc, _ = self.ready()
        self.assertEqual((1, ["timvisher_gh_pr_missing"]), (rc, self.codes()))

    def test_an_omitted_target_is_the_worktrees_pr(self):
        self.checks([("build", "pass")])
        self.assertEqual((0, f"{PR}\n"), self.ready(), self.err)

    def test_a_later_push_keeps_the_pr_ready(self):
        self.github._update(lambda s: s["responses"].clear())
        self.github.respond(["pr", "list"], stdout="[]")
        git("commit", "-q", "--allow-empty", "-m", "work", cwd=self.work)
        (self.work / "pr.md").write_text("New\n\nBody\n")
        rc, out, err = self.run_gh("pr", "push", TIMVISHER_AGENT="1")
        self.assertEqual(0, rc, err)
        url = out.strip()
        number = url.rsplit("/", 1)[-1]
        self.github.respond(["pr", "checks"], stdout=json.dumps([{"name": "b", "bucket": "pass"}]))
        self.assertEqual(0, self.ready(url)[0], self.err)
        self.assertEqual(0, self.run_gh("pr", "push", TIMVISHER_AGENT="1")[0])
        self.assertFalse(self.github.state["pulls"][REPO][number]["draft"])


if __name__ == "__main__":
    unittest.main()
