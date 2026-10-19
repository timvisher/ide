import json
import unittest

from support.case import GhTestCase
from support.remotes import commit_on_remote, git
from timvisher.gh import state

REPO = "testuser/testrepo"
PR1 = f"https://github.com/{REPO}/pull/1"

FAKE_BROWSER = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$FAKE_BROWSER_LOG"
printf '%s\\n' "$2"
"""


class PrTest(GhTestCase):
    def setUp(self):
        super().setUp()
        self.browser_log = self.tmp / "browser.log"
        fake = self.github.bin / "timvisher_browser"
        fake.write_text(FAKE_BROWSER)
        fake.chmod(0o755)
        git("checkout", "-q", "-b", "feature", cwd=self.work)
        git("commit", "-q", "--allow-empty", "-m", "work", cwd=self.work)
        self.github.respond(["pr", "list"], stdout="[]")

    def pr(self, *args):
        rc, out, err = self.run_gh("pr", *args, TIMVISHER_AGENT="1", FAKE_BROWSER_LOG=str(self.browser_log))
        self.err = err
        return rc, out

    def codes(self):
        return [json.loads(line)["code"] for line in self.err.splitlines() if line.startswith('{"type":"instruction"')]

    def pull_state(self, number=1):
        return self.github.state["pulls"][REPO][str(number)]

    def mutations(self):
        return [c for c in self.github.calls
                if c.get("method") in ("POST", "PATCH", "DELETE") and c.get("path") != "graphql"
                or (c.get("path") == "graphql" and "mutation" in c.get("fields", {}).get("query", ""))]

    def create(self, *flags, text="Title\n\nBody\n"):
        (self.work / "pr.md").write_text(text)
        return self.pr(*flags)

    def test_the_first_push_creates_a_draft_pr_and_promotes_pr_md(self):
        rc, out = self.create()
        self.assertEqual((0, f"{PR1}\n"), (rc, out), self.err)
        pull = self.pull_state()
        self.assertEqual(("Title", "Body", True, "main", "feature"),
                         (pull["title"], pull["body"], pull["draft"], pull["base"], pull["head"]))
        self.assertEqual(git("rev-parse", "HEAD", cwd=self.work), git("rev-parse", "feature", cwd=self.remote))
        self.assertTrue((self.work / "pr.md").is_symlink())
        self.assertEqual("Title\n\nBody\n", (self.work / "pr.md").read_text())
        link = self.work / ".timvisher_gh" / "pr"
        self.assertEqual((self.work / "pr.md").resolve().parent, link.resolve())

    def test_creation_honors_ready_for_review_and_base(self):
        git("push", "-q", "origin", "HEAD:refs/heads/dev", cwd=self.work)
        rc, _ = self.create("push", "--ready-for-review", "--base", "dev")
        self.assertEqual(0, rc, self.err)
        self.assertEqual((False, "dev"), (self.pull_state()["draft"], self.pull_state()["base"]))

    def test_push_sends_title_and_body_changes(self):
        self.create()
        (self.work / "pr.md").write_text("New title\n\nNew body\n")
        rc, out = self.pr("push")
        self.assertEqual((0, f"{PR1}\n"), (rc, out), self.err)
        self.assertEqual(("New title", "New body"), (self.pull_state()["title"], self.pull_state()["body"]))
        mark = len(self.github.calls)
        self.assertEqual(0, self.pr("push")[0])
        self.assertEqual([], [c for c in self.github.calls[mark:] if c.get("method") == "PATCH"])

    def test_draft_and_base_flags_are_kept_as_source_state(self):
        self.create()
        git("push", "-q", "origin", "HEAD:refs/heads/dev", cwd=self.work)
        self.assertEqual(0, self.pr("push", "--ready-for-review", "--base", "dev")[0], self.err)
        self.assertEqual((False, "dev"), (self.pull_state()["draft"], self.pull_state()["base"]))
        self.assertEqual(0, self.pr("push")[0], self.err)
        self.assertEqual((False, "dev"), (self.pull_state()["draft"], self.pull_state()["base"]))
        self.assertEqual(0, self.pr("push", "--draft")[0], self.err)
        self.assertTrue(self.pull_state()["draft"])

    def test_a_change_on_github_is_refused_by_push_and_written_by_pull(self):
        self.create()
        self.github._update(lambda s: s["pulls"][REPO]["1"].update(title="Edited on GitHub"))
        rc, _ = self.pr("push")
        self.assertEqual(4, rc)
        self.assertIn("timvisher_gh_push_refused", self.codes())
        self.assertEqual(0, self.pr("pull")[0], self.err)
        self.assertEqual("Edited on GitHub\n\nBody\n", (self.work / "pr.md").read_text())

    def test_pull_mirrors_the_conversation_into_the_store(self):
        self.create()
        gh = self.github
        mine = gh.add_issue_comment(REPO, 1, "mine")
        theirs = gh.add_issue_comment(REPO, 1, "theirs", user="alice")
        root = gh.add_review_comment(REPO, 1, "nit", path="a.go", line=3, user="bob")
        gh.add_review_comment(REPO, 1, "done", reply_to=root)
        gh.add_review(REPO, 1, user="carol", state="APPROVED", body="LGTM")
        self.assertEqual(0, self.pr("pull")[0], self.err)
        pr_dir = (self.work / ".timvisher_gh" / "pr").resolve()
        bodies = sorted(p.read_text() for p in pr_dir.rglob("*.md") if p.name != "pr.md")
        self.assertEqual(["LGTM\n", "done\n", "mine\n", "nit\n", "theirs\n"], bodies)
        self.assertEqual(1, len(list(pr_dir.glob("threads/*/replies/*/comment.md"))))
        gh._update(lambda s: s["issue_comments"].pop(str(theirs)))
        self.assertEqual(0, self.pr("pull")[0], self.err)
        archived = state.root() / "archive"
        self.assertEqual(["theirs\n"], [p.read_text() for p in archived.rglob("comment.md")])
        self.assertTrue(any(f"issuecomment-{mine}" in p.read_text() for p in pr_dir.rglob("comment.url")))

    def test_pull_keeps_local_edits_to_your_comments_and_reports_them(self):
        self.create()
        comment = self.github.add_issue_comment(REPO, 1, "mine")
        self.pr("pull")
        path = next(p for p in (self.work / ".timvisher_gh" / "pr").resolve().rglob("comment.md"))
        path.write_text("edited\n")
        self.assertEqual(0, self.pr("pull")[0])
        self.assertEqual("edited\n", path.read_text())
        self.assertIn("timvisher_gh_unpushed", self.codes())
        self.assertEqual("mine", self.github.state["issue_comments"][str(comment)]["body"])

    def test_edit_errors_when_the_pr_doesnt_exist(self):
        (self.work / "pr.md").write_text("T\n")
        rc, _ = self.pr("edit")
        self.assertEqual((1, ["timvisher_gh_pr_missing"]), (rc, self.codes()))
        self.assertEqual({}, self.github.state["pulls"])

    def test_fetch_writes_no_files(self):
        self.create()
        self.github._update(lambda s: s["pulls"][REPO]["1"].update(title="Edited on GitHub"))
        self.github.add_issue_comment(REPO, 1, "new")
        rc, out = self.pr("fetch")
        self.assertEqual((0, f"{PR1}\n"), (rc, out))
        self.assertEqual("Title\n\nBody\n", (self.work / "pr.md").read_text())
        self.assertEqual([], list((self.work / ".timvisher_gh" / "pr").resolve().rglob("comment.md")))

    def test_open_opens_the_pr(self):
        self.assertEqual(0, self.create("--open")[0], self.err)
        self.assertEqual(f"tab {PR1}\n", self.browser_log.read_text())

    def test_without_open_no_browser_is_used(self):
        self.create()
        self.assertFalse(self.browser_log.exists())

    def test_plan_changes_nothing(self):
        rc, out = self.create("--plan")
        self.assertEqual(0, rc, self.err)
        self.assertIn("+ pr", out)
        self.assertEqual(({}, []), (self.github.state["pulls"], self.mutations()))
        self.pr("push")
        (self.work / "pr.md").write_text("Changed\n\nBody\n")
        mark = len(self.github.calls)
        rc, out = self.pr("push", "--plan")
        self.assertEqual(0, rc)
        self.assertIn(f"~ pr      {PR1}", out)
        self.assertEqual([], [c for c in self.github.calls[mark:] if c.get("method") == "PATCH"])

    def test_a_failed_branch_push_fails_the_sync(self):
        self.create()
        commit_on_remote(self.tmp, self.remote, "feature", "someone else's")
        git("commit", "-q", "--amend", "--allow-empty", "-m", "rewritten", cwd=self.work)
        (self.work / "pr.md").write_text("Changed\n\nBody\n")
        rc, _ = self.pr("push")
        self.assertNotEqual(0, rc)
        self.assertEqual("Title", self.pull_state()["title"])

    def test_your_comments_on_someone_elses_pr_are_yours(self):
        self.github.add_pull(REPO, 5, head="theirs", title="Theirs", author="alice")
        url = f"https://github.com/{REPO}/pull/5"
        mine = self.github.add_issue_comment(REPO, 5, "mine")
        self.github.add_issue_comment(REPO, 5, "by the author", user="alice")
        self.pr("pull", url)
        path = next(p for p in state.root().rglob("comment.md") if p.read_text() == "mine\n")
        path.write_text("my edit\n")
        self.github._update(lambda s: s["issue_comments"][str(mine)].update(body="edited on GitHub"))
        rc, _ = self.pr("pull", url)
        self.assertEqual(3, rc)
        self.assertEqual("my edit\n", path.read_text())
        self.assertIn("timvisher_gh_sync_conflict", self.codes())

    def test_resolving_an_existing_pr_links_the_worktree(self):
        git("push", "-q", "-u", "origin", "feature", cwd=self.work)
        self.github.add_pull(REPO, 3, head="feature", title="Made on the web")
        self.github._update(lambda s: s.update(responses=[]))
        self.github.respond(["pr", "list"], stdout=json.dumps([{"number": 3, "state": "OPEN"}]))
        self.assertEqual(0, self.pr("pull")[0], self.err)
        link = self.work / ".timvisher_gh" / "pr"
        self.assertTrue(link.is_symlink())
        self.assertEqual("Made on the web\n", (link / "pr.md").read_text())
        mark = len(self.github.calls)
        self.pr("fetch")
        self.assertEqual([], [c for c in self.github.calls[mark:] if c["argv"][2:4] == ["pr", "list"]])

    def test_flags_are_kept_even_when_github_already_matches(self):
        self.create()
        self.github._update(lambda s: s["pulls"][REPO]["1"].update(draft=False))
        self.pr("pull")
        self.assertEqual(0, self.pr("push", "--ready-for-review")[0], self.err)
        self.assertEqual(0, self.pr("push")[0], self.err)
        self.assertFalse(self.pull_state()["draft"])

    def test_fetch_and_pull_with_only_an_untracked_pr_md_have_nothing_to_do(self):
        (self.work / "pr.md").write_text("T\n")
        for verb in ("fetch", "pull"):
            rc, out = self.pr(verb)
            self.assertEqual((0, ""), (rc, out), verb)
            self.assertIn("timvisher_gh_nothing_to_do", self.codes())
        self.assertEqual({}, self.github.state["pulls"])

    def test_a_partial_thread_page_archives_nothing(self):
        self.create()
        root = self.github.add_review_comment(REPO, 1, "nit", user="bob")
        self.pr("pull")
        self.github._update(lambda s: s["threads"].clear())
        self.github._update(lambda s: s.update(partial_threads=True))
        self.assertEqual(0, self.pr("pull")[0], self.err)
        self.assertFalse((state.root() / "archive").exists())
        del root

    def test_someone_elses_pr_is_only_pulled(self):
        self.github.add_pull(REPO, 5, head="theirs", title="Theirs", author="alice")
        url = f"https://github.com/{REPO}/pull/5"
        self.assertEqual(0, self.pr("pull", url)[0], self.err)
        self.assertEqual(0, self.pr("push", url)[0], self.err)
        self.assertEqual([], self.mutations())
        self.assertNotIn("feature", git("ls-remote", "--heads", "origin", cwd=self.work))


if __name__ == "__main__":
    unittest.main()
