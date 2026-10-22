import json
import unittest

from support.case import GhTestCase
from support.remotes import git

REPO = "testuser/testrepo"
PR = f"https://github.com/{REPO}/pull/7"


class CloseTest(GhTestCase):
    def setUp(self):
        super().setUp()
        git("checkout", "-q", "-b", "feature", cwd=self.work)
        self.github.add_pull(REPO, 7, head="feature", title="T")
        self.github.respond(["pr", "list"], stdout=json.dumps([{"number": 7, "state": "OPEN"}]))

    def run_noun(self, *args, stdin=None):
        rc, out, err = self.run_gh(*args, TIMVISHER_AGENT="1", stdin=stdin)
        self.err = err
        return rc, out

    def codes(self):
        return [json.loads(line)["code"] for line in self.err.splitlines() if line.startswith('{"type":"instruction"')]

    def writes(self):
        return [c for c in self.github.calls if c.get("method") in ("POST", "PATCH", "DELETE")]

    def pull_state(self):
        return self.github.state["pulls"][REPO]["7"]["state"]

    def test_pr_close_closes_the_worktrees_pr_and_refreshes_its_record(self):
        self.assertEqual((0, f"{PR}\n"), self.run_noun("pr", "close"), self.err)
        self.assertEqual("closed", self.pull_state())
        self.assertIn("timvisher_gh_closed", self.codes())
        self.assertEqual("closed\n", self.run_gh("pr", "info", PR, ".state")[1])

    def test_pr_close_and_reopen_are_idempotent(self):
        self.assertEqual(0, self.run_noun("pr", "close", PR)[0], self.err)
        mark = len(self.writes())
        self.assertEqual((0, f"{PR}\n"), self.run_noun("pr", "close", PR), self.err)
        self.assertEqual((["timvisher_gh_already_closed"], mark), (self.codes(), len(self.writes())))
        self.assertEqual((0, f"{PR}\n"), self.run_noun("pr", "reopen", PR), self.err)
        self.assertEqual(("open", ["timvisher_gh_reopened"]), (self.pull_state(), self.codes()))
        self.assertEqual("open\n", self.run_gh("pr", "info", PR, ".state")[1])
        mark = len(self.writes())
        self.assertEqual(0, self.run_noun("pr", "reopen", PR)[0], self.err)
        self.assertEqual((["timvisher_gh_already_open"], mark), (self.codes(), len(self.writes())))

    def test_pr_close_works_on_someone_elses_pr(self):
        self.github.add_pull(REPO, 8, head="theirs", title="O", author="alice")
        self.assertEqual(0, self.run_noun("pr", "close", f"https://github.com/{REPO}/pull/8")[0], self.err)
        self.assertEqual("closed", self.github.state["pulls"][REPO]["8"]["state"])

    def test_pr_plan_changes_nothing(self):
        self.assertEqual((0, f"~ pr      {PR}  close\n"), self.run_noun("pr", "close", "--plan"), self.err)
        self.assertEqual(f"  pr      {PR}  unchanged: already open\n", self.run_noun("pr", "reopen", "--plan")[1])
        self.assertEqual(("open", []), (self.pull_state(), self.writes()))

    def test_a_merged_pr_is_already_closed_and_cant_be_reopened(self):
        self.github.update_pull(REPO, 7, state="closed", merged=True, merged_at="2026-10-10T10:00:00Z",
                                merge_commit_sha="m" * 40)
        self.assertEqual(0, self.run_noun("pr", "close")[0], self.err)
        self.assertEqual(["timvisher_gh_already_closed"], self.codes())
        self.assertEqual((1, ""), self.run_noun("pr", "reopen"))
        self.assertEqual(["timvisher_gh_pr_merged"], self.codes())
        self.assertEqual([], self.writes())

    def test_pr_close_refuses_extra_arguments_and_documents_itself(self):
        self.assertEqual(2, self.run_noun("pr", "close", PR, PR)[0])
        self.assertEqual(2, self.run_noun("pr", "close", "--force")[0])
        rc, out = self.run_noun("pr", "close", "--help")
        self.assertEqual(0, rc)
        self.assertIn("--plan", out)
        self.assertIn("close", self.run_noun("pr", "--help")[1])
        self.assertIn("reopen", self.run_noun("pr", "--help")[1])


if __name__ == "__main__":
    unittest.main()
