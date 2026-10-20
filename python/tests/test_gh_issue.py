import json
import unittest

from support.case import GhTestCase

REPO = "testuser/testrepo"
ISSUE1 = f"https://github.com/{REPO}/issues/1"

FAKE_BROWSER = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$FAKE_BROWSER_LOG"
printf '%s\\n' "$2"
"""


class IssueTest(GhTestCase):
    def setUp(self):
        super().setUp()
        self.browser_log = self.tmp / "browser.log"
        fake = self.github.bin / "timvisher_browser"
        fake.write_text(FAKE_BROWSER)
        fake.chmod(0o755)

    def issue(self, *args):
        rc, out, err = self.run_gh("issue", *args, TIMVISHER_AGENT="1", FAKE_BROWSER_LOG=str(self.browser_log))
        self.err = err
        return rc, out

    def codes(self):
        return [json.loads(line)["code"] for line in self.err.splitlines() if line.startswith('{"type":"instruction"')]

    def on_github(self, number=1):
        return self.github.state["issues"][REPO][str(number)]

    def create(self, *flags):
        (self.work / "issue.md").write_text("Bug\n\nIt breaks\n")
        return self.issue(*flags)

    def test_the_first_sync_creates_the_issue_and_promotes_issue_md(self):
        rc, out = self.create()
        self.assertEqual((0, f"{ISSUE1}\n"), (rc, out), self.err)
        self.assertEqual(("Bug", "It breaks"), (self.on_github()["title"], self.on_github()["body"]))
        self.assertTrue((self.work / "issue.md").is_symlink())
        self.assertEqual("Bug\n\nIt breaks\n", (self.work / "issue.md").read_text())

    def test_a_new_issue_md_after_the_first_files_a_second_issue(self):
        self.create()
        (self.work / "issue.md").unlink()
        (self.work / "issue.md").write_text("Another bug\n\nAlso breaks\n")
        rc, out = self.issue()
        self.assertEqual((0, f"https://github.com/{REPO}/issues/2\n"), (rc, out), self.err)
        self.assertEqual(("Bug", "Another bug"), (self.on_github(1)["title"], self.on_github(2)["title"]))
        self.assertTrue((self.work / "issue.md").is_symlink())
        self.assertEqual("2\n", self.issue("info", ".number")[1])
        (self.work / "issue.md").write_text("Another bug, edited\n\nAlso breaks\n")
        (self.work / "issue.md").unlink()
        self.assertEqual("2\n", self.issue("info", ".number")[1])

    def test_push_sends_title_and_body(self):
        self.create("push")
        (self.work / "issue.md").write_text("Bug, worse\n\nIt really breaks\n")
        self.assertEqual((0, f"{ISSUE1}\n"), self.issue("push"), self.err)
        self.assertEqual(("Bug, worse", "It really breaks"), (self.on_github()["title"], self.on_github()["body"]))

    def test_pull_writes_githubs_changes(self):
        self.create()
        self.github._update(lambda s: s["issues"][REPO]["1"].update(body="Edited on GitHub"))
        self.assertEqual(0, self.issue("pull")[0], self.err)
        self.assertEqual("Bug\n\nEdited on GitHub\n", (self.work / "issue.md").read_text())

    def test_sync_pulls_then_pushes(self):
        self.create()
        self.github._update(lambda s: s["issues"][REPO]["1"].update(title="Renamed on GitHub"))
        (self.work / "issue.md").write_text("Bug\n\nMy new body\n")
        self.assertEqual(0, self.issue()[0], self.err)
        self.assertEqual("Renamed on GitHub\n\nMy new body\n", (self.work / "issue.md").read_text())
        self.assertEqual(("Renamed on GitHub", "My new body"), (self.on_github()["title"], self.on_github()["body"]))

    def test_the_same_field_changed_on_both_sides_is_a_decision(self):
        self.create()
        self.github._update(lambda s: s["issues"][REPO]["1"].update(body="Theirs"))
        (self.work / "issue.md").write_text("Bug\n\nMine\n")
        self.assertEqual(3, self.issue()[0])
        self.assertIn("timvisher_gh_sync_conflict", self.codes())
        self.assertEqual(0, self.issue("--ours")[0], self.err)
        self.assertEqual("Mine", self.on_github()["body"])

    def test_push_refuses_githubs_changes(self):
        self.create()
        self.github._update(lambda s: s["issues"][REPO]["1"].update(title="Renamed on GitHub"))
        self.assertEqual(4, self.issue("push")[0])

    def test_edit_errors_when_the_issue_doesnt_exist(self):
        (self.work / "issue.md").write_text("T\n")
        self.assertEqual(1, self.issue("edit")[0])
        self.assertEqual(["timvisher_gh_issue_missing"], self.codes())
        self.assertEqual({}, self.github.state["issues"])

    def test_fetch_writes_no_files(self):
        self.create()
        self.github._update(lambda s: s["issues"][REPO]["1"].update(body="Edited on GitHub"))
        self.assertEqual((0, f"{ISSUE1}\n"), self.issue("fetch"))
        self.assertEqual("Bug\n\nIt breaks\n", (self.work / "issue.md").read_text())

    def test_info(self):
        self.create()
        rc, out = self.issue("info", ".title")
        self.assertEqual((0, "Bug\n"), (rc, out), self.err)

    def test_a_url_target_works_and_someone_elses_issue_is_only_pulled(self):
        self.github.add_issue(REPO, 9, title="Theirs", body="b", author="alice")
        url = f"https://github.com/{REPO}/issues/9"
        self.assertEqual(0, self.issue("push", url)[0], self.err)
        self.assertFalse([c for c in self.github.calls if c.get("method") == "PATCH"])

    def test_open_opens_the_issue(self):
        self.assertEqual(0, self.create("--open")[0], self.err)
        self.assertEqual(f"tab {ISSUE1}\n", self.browser_log.read_text())

    def test_plan_changes_nothing(self):
        rc, out = self.create("--plan")
        self.assertEqual(0, rc, self.err)
        self.assertIn("+ issue", out)
        self.assertEqual({}, self.github.state["issues"])


if __name__ == "__main__":
    unittest.main()
