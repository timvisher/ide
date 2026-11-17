import json
import unittest

from support.case import GhTestCase
from support.remotes import git

REPO = "testuser/testrepo"
PR = f"https://github.com/{REPO}/pull/7"
ISSUE = f"https://github.com/{REPO}/issues/1"


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

    def issue_state(self):
        found = self.github.state["issues"][REPO]["1"]
        return found["state"], found["state_reason"]

    def issue_info(self, component):
        return self.run_gh("issue", "info", ISSUE, component)[1].strip()

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

    def test_issue_close_closes_and_refreshes_the_record(self):
        self.github.add_issue(REPO, 1, title="Bug")
        self.assertEqual((0, f"{ISSUE}\n"), self.run_noun("issue", "close", ISSUE), self.err)
        self.assertEqual(("closed", "completed"), self.issue_state())
        self.assertEqual(["timvisher_gh_closed"], self.codes())
        self.assertEqual(("closed", "completed"), (self.issue_info(".state"), self.issue_info(".state_reason")))
        mark = len(self.writes())
        self.assertEqual((0, f"{ISSUE}\n"), self.run_noun("issue", "close", ISSUE), self.err)
        self.assertEqual((["timvisher_gh_already_closed"], mark), (self.codes(), len(self.writes())))

    def test_issue_close_on_a_transferred_issue_closes_it_where_it_went(self):
        self.github.add_repo("testuser/elsewhere")
        self.github.add_issue("testuser/elsewhere", 50, title="Moved")
        self.github.add_issue(REPO, 50, title="Unrelated")
        self.github.add_issue(REPO, 1, title="Bug", moved_to=["testuser/elsewhere", 50])
        self.assertEqual((0, "https://github.com/testuser/elsewhere/issues/50\n"),
                         self.run_noun("issue", "close", ISSUE), self.err)
        self.assertEqual(("closed", "open"), (self.github.state["issues"]["testuser/elsewhere"]["50"]["state"],
                                              self.github.state["issues"][REPO]["50"]["state"]))

    def test_issue_close_with_a_reason_converges_on_it(self):
        self.github.add_issue(REPO, 1, title="Bug")
        self.assertEqual(0, self.run_noun("issue", "close", ISSUE, "--reason", "not_planned")[0], self.err)
        self.assertEqual(("closed", "not_planned"), self.issue_state())
        mark = len(self.writes())
        self.assertEqual(0, self.run_noun("issue", "close", ISSUE, "--reason=not_planned")[0], self.err)
        self.assertEqual(0, self.run_noun("issue", "close", ISSUE)[0], self.err)
        self.assertEqual(mark, len(self.writes()))
        self.assertEqual(0, self.run_noun("issue", "close", "--reason", "completed", ISSUE)[0], self.err)
        self.assertEqual((("closed", "completed"), mark + 1), (self.issue_state(), len(self.writes())))
        self.assertEqual("completed", self.issue_info(".state_reason"))

    def test_issue_reopen_is_idempotent_and_takes_no_reason(self):
        self.github.add_issue(REPO, 1, title="Bug", state="closed", state_reason="completed",
                              closed_at="2026-10-10T10:00:00Z")
        self.assertEqual((0, f"{ISSUE}\n"), self.run_noun("issue", "reopen", ISSUE), self.err)
        self.assertEqual((("open", "reopened"), ["timvisher_gh_reopened"]), (self.issue_state(), self.codes()))
        self.assertEqual("open", self.issue_info(".state"))
        mark = len(self.writes())
        self.assertEqual(0, self.run_noun("issue", "reopen", ISSUE)[0], self.err)
        self.assertEqual((["timvisher_gh_already_open"], mark), (self.codes(), len(self.writes())))
        self.assertEqual(2, self.run_noun("issue", "reopen", ISSUE, "--reason", "completed")[0])

    def test_issue_close_rejects_an_unknown_reason_before_any_api_call(self):
        self.github.add_issue(REPO, 1, title="Bug")
        mark = len(self.github.calls)
        self.assertEqual(2, self.run_noun("issue", "close", ISSUE, "--reason", "duplicate")[0])
        self.assertEqual(2, self.run_noun("issue", "close", ISSUE, "--reason")[0])
        self.assertEqual([], self.github.calls[mark:])

    def test_issue_plan_changes_nothing(self):
        self.github.add_issue(REPO, 1, title="Bug")
        self.assertEqual((0, f"~ issue   {ISSUE}  close as not_planned\n"),
                         self.run_noun("issue", "close", ISSUE, "--reason", "not_planned", "--plan"), self.err)
        self.assertEqual(f"  issue   {ISSUE}  unchanged: already open\n",
                         self.run_noun("issue", "reopen", ISSUE, "--plan")[1])
        self.assertEqual((("open", None), []), (self.issue_state(), self.writes()))
        self.github._update(lambda s: s["issues"][REPO]["1"].update(state="closed", state_reason="completed"))
        self.assertEqual(f"~ issue   {ISSUE}  change the reason from completed to not_planned\n",
                         self.run_noun("issue", "close", ISSUE, "--reason", "not_planned", "--plan")[1])
        self.assertEqual([], self.writes())

    def test_issue_close_targets_the_worktrees_issue_and_refuses_a_pr(self):
        (self.work / "issue.md").write_text("Bug\n\nIt breaks\n")
        rc, url = self.run_noun("issue")
        self.assertEqual(0, rc, self.err)
        self.assertEqual((0, url), self.run_noun("issue", "close"), self.err)
        self.assertEqual("closed", self.github.state["issues"][REPO][url.strip().split("/")[-1]]["state"])
        self.assertEqual(2, self.run_noun("issue", "close", PR)[0])
        self.assertEqual("open", self.pull_state())

    def test_issue_close_documents_itself(self):
        rc, out = self.run_noun("issue", "close", "--help")
        self.assertEqual(0, rc)
        self.assertIn("--reason completed|not_planned", out)
        self.assertIn("reopen", self.run_noun("issue", "--help")[1])


if __name__ == "__main__":
    unittest.main()
