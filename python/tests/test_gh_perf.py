import json
import unittest

from support.case import GhTestCase
from support.remotes import git

REPO = "testuser/testrepo"
PR = f"https://github.com/{REPO}/pull/7"


class PerfTest(GhTestCase):
    def setUp(self):
        super().setUp()
        git("checkout", "-q", "-b", "feature", cwd=self.work)
        self.github.add_pull(REPO, 7, head="feature", title="T")
        self.github.respond(["pr", "list"], stdout=json.dumps([{"number": 7, "state": "OPEN"}]))
        self.logs = self.tmp / "logs"

    def run_logged(self, *args, **env):
        rc, out, err = self.run_gh(*args, TIMVISHER_TOOL_LOG_DIR=str(self.logs), **env)
        return rc, err

    def runs(self):
        return [json.loads(line) for line in (self.logs / "timvisher_gh.jsonl").read_text().splitlines()]

    def test_a_pr_fetch_logs_one_line_with_its_phases_gh_calls_and_lock(self):
        liked = self.github.add_issue_comment(REPO, 7, "nice")
        self.github.add_issue_comment(REPO, 7, "plan output")
        self.github.add_reaction("issue_comment", liked, "heart", user="testuser")
        rc, err = self.run_logged("pr", "fetch", PR)
        self.assertEqual(0, rc, err)

        [run] = self.runs()
        self.assertEqual(("timvisher_gh", ["pr", "fetch", PR], 0, str(self.work)),
                         (run["tool"], run["argv"], run["rc"], run["cwd"]))
        for path in ("open_state", "resolve", "fetch", "fetch/list", "fetch/items", "export", "viewer"):
            self.assertIn(path, run["phases"])
        gh_calls = len([c for c in self.github.calls if c.get("path") or c.get("args")])
        self.assertEqual(gh_calls, run["calls"]["gh"]["n"])
        self.assertEqual(4, run["phases"]["fetch/list"]["calls"]["gh"]["n"])
        reaction_and_viewer = 2
        self.assertEqual(reaction_and_viewer, run["phases"]["fetch/items"]["calls"]["gh"]["n"])
        self.assertLessEqual(1, run["lock"]["n"])
        self.assertLessEqual(run["lock"]["max_held_ms"], run["lock"]["held_ms"])
        self.assertLessEqual(run["phases"]["fetch"]["ms"], run["duration_ms"])
        self.assertLessEqual(0, run["unphased_ms"])

    def test_its_line_matches_the_shims_fields_so_its_gh_calls_join_on_caller_and_time(self):
        self.run_logged("pr", "fetch", PR, CLAUDE_CODE_SESSION_ID="s-1", CLAUDE_PID="")
        [run] = self.runs()
        self.assertEqual({"kind": "claude", "session_id": "s-1"}, run["caller"])
        for field in ("ts", "epoch", "real", "duration_ms", "host", "pid"):
            self.assertIn(field, run)
        self.assertRegex(run["ts"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$")

    def test_a_failed_run_logs_its_exit_status(self):
        rc, _ = self.run_logged("pr", "fetch", f"https://github.com/{REPO}/pull/99")
        self.assertNotEqual(0, rc)
        [run] = self.runs()
        self.assertEqual(rc, run["rc"])

    def test_every_run_appends_its_own_line(self):
        self.run_logged("pr", "fetch", PR)
        self.run_logged("pr", "info", PR, ".title")
        self.assertEqual([["pr", "fetch", PR], ["pr", "info", PR, ".title"]], [r["argv"] for r in self.runs()])

    def test_a_log_dir_it_cant_write_warns_and_keeps_the_result(self):
        self.logs.write_text("not a directory")
        rc, err = self.run_logged("pr", "fetch", PR)
        self.assertEqual(0, rc, err)
        self.assertIn("timvisher_gh: could not append to", err)


if __name__ == "__main__":
    unittest.main()
