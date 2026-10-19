import contextlib
import io
import json
import os
import unittest
from unittest import mock

from support.case import GhTestCase
from support.remotes import git
from timvisher.gh import repo, state, targets
from timvisher.gh.errors import Exit

PR = "https://github.com/O/R/pull/7"

FAKE_BROWSER = """#!/usr/bin/env bash
[[ -n ${FAKE_TAB_URL-} ]] || { echo 'not running' >&2; exit 1; }
printf '{"schema_version": 1, "url": "%s", "title": "t", "browser": "Vivaldi"}\\n' "$FAKE_TAB_URL"
"""


class TargetsTest(GhTestCase):
    def setUp(self):
        super().setUp()
        fake = self.github.bin / "timvisher_browser"
        fake.write_text(FAKE_BROWSER)
        fake.chmod(0o755)
        patcher = mock.patch.dict(os.environ, {**self.env(), "TIMVISHER_AGENT": "1"})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.context = repo.from_worktree(str(self.work))
        self.db = state.open_state()
        self.addCleanup(self.db.close)

    def resolve(self, noun, argument=None, creating=False):
        return targets.resolve(noun, argument, context=self.context, db=self.db.db, creating=creating)

    def refused(self, noun, argument=None, creating=False):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr), self.assertRaises(Exit) as raised:
            self.resolve(noun, argument, creating)
        lines = [json.loads(line) for line in stderr.getvalue().splitlines() if line.startswith("{")]
        return raised.exception.status, lines[-1]

    def track(self, object_id, url, store_path, authored=None):
        with self.db.write() as db:
            db.execute("INSERT INTO objects (id, kind, url, owner, repo, store_path) VALUES (?, 'pr', ?, 'O', 'R', ?)",
                       (object_id, url, store_path))
            if authored is not None:
                db.execute("INSERT INTO authored VALUES (?, ?)", (object_id, str(authored)))

    def tab(self, url):
        os.environ["FAKE_TAB_URL"] = url

    def test_pr_urls_with_their_suffixes(self):
        for url in (PR, f"{PR}/files", f"{PR}/changes", f"{PR}/commits", f"{PR}?w=1", f"{PR}#top",
                    f"{PR}/files?diff=split#diff-abc"):
            target = self.resolve("pr", url)
            self.assertEqual(("pr", "O", "R", 7, PR), (target.kind, target.owner, target.repo, target.number, target.url), url)

    def test_issue_urls_with_their_suffixes(self):
        for url in ("https://github.com/O/R/issues/3", "https://github.com/O/R/issues/3?notification_referrer_id=x",
                    "https://github.com/O/R/issues/3#issuecomment-9", "https://github.com/O/R/issues/3?q=1#top"):
            target = self.resolve("issue", url)
            self.assertEqual(("issue", 3, "https://github.com/O/R/issues/3"), (target.kind, target.number, target.url),
                             url)

    def test_comment_urls(self):
        top = self.resolve("comment", f"{PR}/files?x=1#issuecomment-55")
        self.assertEqual(("comment", 55, f"{PR}#issuecomment-55", PR), (top.kind, top.comment_id, top.url, top.pr_url))
        review = self.resolve("comment", f"{PR}/changes#discussion_r66")
        self.assertEqual(("review_comment", 66, f"{PR}#discussion_r66"), (review.kind, review.comment_id, review.url))

    def test_thread_urls_are_their_root_comments_discussion_url(self):
        thread = self.resolve("thread", f"{PR}#discussion_r66")
        self.assertEqual(("thread", 66, f"{PR}#discussion_r66"), (thread.kind, thread.comment_id, thread.url))

    def test_a_top_level_comment_is_not_a_thread(self):
        status, instruction = self.refused("thread", f"{PR}#issuecomment-55")
        self.assertEqual((2, "timvisher_gh_target_not_a_thread"), (status, instruction["code"]))

    def test_other_urls_are_errors_that_show_the_accepted_shapes(self):
        for url in ("https://gitlab.com/O/R/pull/7", "http://github.com/O/R/pull/7", "https://github.com/O/R",
                    "https://github.com/O/R/pull/7/checks", "https://github.com/O/R/issues/3/timeline"):
            status, instruction = self.refused("pr", url)
            self.assertEqual((2, "timvisher_gh_target_invalid_url"), (status, instruction["code"]), url)
            self.assertEqual(len(targets.SHAPES), len(instruction["suggestions"]))

    def test_the_current_browser_tab_resolves_by_url(self):
        self.tab(f"{PR}#discussion_r66")
        target = self.resolve("comment", targets.BROWSER_TAB)
        self.assertEqual(("review_comment", 66, "browser"), (target.kind, target.comment_id, target.via))

    def test_a_current_browser_tab_that_is_not_github_says_where_it_came_from(self):
        self.tab("https://example.com/")
        status, instruction = self.refused("pr", targets.BROWSER_TAB)
        self.assertEqual((2, "timvisher_gh_target_invalid_url"), (status, instruction["code"]))
        self.assertIn("the current browser tab", instruction["message"])

    def test_an_unreadable_browser_tab_is_an_error(self):
        status, instruction = self.refused("pr", targets.BROWSER_TAB)
        self.assertEqual((1, "timvisher_gh_target_browser_failed"), (status, instruction["code"]))

    def test_an_authored_symlink_is_tracked(self):
        store = state.root() / "github.com/O/R/pull/7"
        store.mkdir(parents=True)
        (store / "pr.md").write_text("T\n")
        link = self.work / "pr.md"
        link.symlink_to(store / "pr.md")
        self.track("PR_7", PR, "github.com/O/R/pull/7", authored=link.absolute())
        target = self.resolve("pr", str(link))
        self.assertEqual(("pr", 7, "PR_7", "tracked"), (target.kind, target.number, target.object_id, target.via))

    def test_a_store_path_and_a_path_through_the_worktree_link_are_tracked(self):
        store = state.root() / "github.com/O/R/pull/7"
        store.mkdir(parents=True)
        (store / "pr.md").write_text("T\n")
        self.track("PR_7", PR, "github.com/O/R/pull/7")
        (self.work / ".timvisher_gh").mkdir()
        (self.work / ".timvisher_gh" / "pr").symlink_to(store)
        for path in (store / "pr.md", self.work / ".timvisher_gh" / "pr" / "pr.md"):
            self.assertEqual(("PR_7", "tracked"), (lambda t: (t.object_id, t.via))(self.resolve("pr", str(path))), path)

    def test_a_file_inside_an_objects_store_directory_is_that_object(self):
        thread = state.root() / "github.com/O/R/pull/7/threads/t1"
        thread.mkdir(parents=True)
        (thread / "root-comment.md").write_text("nit\n")
        with self.db.write() as db:
            db.execute("INSERT INTO objects (id, kind, url, owner, repo, store_path) VALUES "
                       "('PRRT_1', 'thread', ?, 'O', 'R', 'github.com/O/R/pull/7/threads/t1')", (f"{PR}#discussion_r66",))
        target = self.resolve("thread", str(thread / "root-comment.md"))
        self.assertEqual(("thread", 66, "PRRT_1"), (target.kind, target.comment_id, target.object_id))

    def test_a_file_deeper_in_an_objects_directory_is_not_that_object(self):
        drafts = state.root() / "github.com/O/R/pull/7/comments"
        drafts.mkdir(parents=True)
        (drafts / "draft.md").write_text("new\n")
        self.track("PR_7", PR, "github.com/O/R/pull/7")
        target = self.resolve("comment", str(drafts / "draft.md"), creating=True)
        self.assertEqual("source", target.kind)

    def test_a_legacy_url_beside_the_file_names_its_object(self):
        (self.work / "notes.md").write_text("hi\n")
        (self.work / "notes.md.url").write_text(f"{PR}#issuecomment-55\n")
        target = self.resolve("comment", str(self.work / "notes.md"))
        self.assertEqual(("comment", 55, "legacy"), (target.kind, target.comment_id, target.via))

    def test_an_untracked_file_is_a_source_only_when_creating(self):
        source = self.work / "reply.md"
        source.write_text("hi\n")
        target = self.resolve("comment", str(source), creating=True)
        self.assertEqual(("source", source, "untracked"), (target.kind, target.source, target.via))
        status, instruction = self.refused("comment", str(source))
        self.assertEqual((2, "timvisher_gh_target_untracked"), (status, instruction["code"]))

    def test_neither_a_url_nor_a_file_is_an_error(self):
        status, instruction = self.refused("pr", "no-such-file.md")
        self.assertEqual((2, "timvisher_gh_target_invalid"), (status, instruction["code"]))
        self.assertTrue(any(targets.BROWSER_TAB in s for s in instruction["suggestions"]))

    def test_omitted_pr_target_comes_from_the_states_worktree_context_first(self):
        self.track("PR_7", PR, "github.com/O/R/pull/7")
        with self.db.write() as db:
            db.execute("INSERT INTO context VALUES (?, 'testuser', 'testrepo', 'main', 'PR_7')",
                       (self.context.toplevel,))
        (self.work / "pr.md").write_text("T\n")
        self.tab("https://github.com/O/R/pull/99")
        target = self.resolve("pr")
        self.assertEqual((7, "PR_7", "context"), (target.number, target.object_id, target.via))
        self.assertFalse(any(c["argv"][2:4] == ["pr", "list"] for c in self.github.calls))

    def test_the_states_context_is_only_for_the_branch_it_recorded(self):
        self.track("PR_7", PR, "github.com/O/R/pull/7")
        with self.db.write() as db:
            db.execute("INSERT INTO context VALUES (?, 'testuser', 'testrepo', 'main', 'PR_7')",
                       (self.context.toplevel,))
        git("checkout", "-q", "-b", "feature", cwd=self.work)
        self.github.respond(["pr", "list"], stdout=json.dumps([{"number": 9, "state": "OPEN"}]))
        self.assertEqual((9, None), (lambda t: (t.number, t.object_id))(self.resolve("pr")))
        git("checkout", "-q", "--detach", cwd=self.work)
        self.tab(PR)
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertEqual("browser", self.resolve("pr").via)

    def test_a_tracked_store_directory_is_its_object(self):
        store = state.root() / "github.com/O/R/pull/7"
        store.mkdir(parents=True)
        self.track("PR_7", PR, "github.com/O/R/pull/7")
        (self.work / ".timvisher_gh").mkdir()
        (self.work / ".timvisher_gh" / "pr").symlink_to(store)
        for path in (store, self.work / ".timvisher_gh" / "pr"):
            self.assertEqual("PR_7", self.resolve("pr", str(path)).object_id, path)
        status, instruction = self.refused("pr", str(self.work))
        self.assertEqual((2, "timvisher_gh_target_invalid"), (status, instruction["code"]))

    def test_an_untracked_root_pr_md_is_skipped_by_commands_that_dont_create(self):
        self.github.respond(["pr", "list"], stdout="[]")
        (self.work / "pr.md").write_text("T\n")
        self.tab(PR)
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertEqual((7, "browser"), (lambda t: (t.number, t.via))(self.resolve("pr")))

    def test_a_renamed_store_directory_still_resolves_by_its_exports_node_id(self):
        renamed = state.root() / "github.com/O/R/pull/7/comments/renamed"
        renamed.mkdir(parents=True)
        (renamed / "comment.md").write_text("hi\n")
        (renamed / "comment.json").write_text(json.dumps({"id": "IC_5"}))
        with self.db.write() as db:
            db.execute("INSERT INTO objects (id, kind, url, owner, repo, store_path) VALUES "
                       "('IC_5', 'comment', ?, 'O', 'R', 'github.com/O/R/pull/7/comments/original')",
                       (f"{PR}#issuecomment-5",))
        self.assertEqual(("IC_5", 5), (lambda t: (t.object_id, t.comment_id))(
            self.resolve("comment", str(renamed / "comment.md"))))

    def test_a_pr_comment_tab_is_its_pr_for_the_pr_fallback(self):
        self.github.respond(["pr", "list"], stdout="[]")
        self.tab(f"{PR}#issuecomment-55")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            target = self.resolve("pr")
        self.assertEqual(("pr", 7, "browser"), (target.kind, target.number, target.via))

    def test_the_browser_fallback_ignores_a_tab_of_another_kind(self):
        self.github.respond(["pr", "list"], stdout="[]")
        self.tab("https://github.com/O/R/issues/4")
        status, instruction = self.refused("pr")
        self.assertEqual((1, "timvisher_gh_target_none"), (status, instruction["code"]))

    def test_omitted_pr_target_then_comes_from_gh_pr_list_head(self):
        git("checkout", "-q", "-b", "feature", cwd=self.work)
        self.github.respond(["pr", "list"], stdout=json.dumps(
            [{"number": 3, "state": "MERGED"}, {"number": 9, "state": "OPEN"}, {"number": 5, "state": "CLOSED"}]))
        target = self.resolve("pr")
        self.assertEqual(("testuser", "testrepo", 9, "context"), (target.owner, target.repo, target.number, target.via))
        self.assertEqual(["-R", "testuser/testrepo", "pr", "list", "--head", "feature", "--state", "all",
                          "--json", "number,state"], self.github.calls[-1]["argv"])

    def test_without_an_open_pr_the_newest_for_the_branch_wins(self):
        self.github.respond(["pr", "list"], stdout=json.dumps([{"number": 3, "state": "MERGED"},
                                                               {"number": 5, "state": "CLOSED"}]))
        self.assertEqual(5, self.resolve("pr").number)

    def test_a_detached_worktree_has_no_pr_context(self):
        git("checkout", "-q", "--detach", cwd=self.work)
        (self.work / "pr.md").write_text("T\n")
        self.assertEqual("untracked", self.resolve("pr", creating=True).via)
        self.assertEqual([], [c for c in self.github.calls if c["argv"][2:4] == ["pr", "list"]])

    def test_omitted_target_then_uses_root_pr_md_or_issue_md(self):
        self.github.respond(["pr", "list"], stdout="[]")
        for noun in ("pr", "issue"):
            (self.work / f"{noun}.md").write_text("T\n")
            target = self.resolve(noun, creating=True)
            self.assertEqual(("source", self.work / f"{noun}.md"), (target.kind, target.source), noun)

    def test_a_tracked_root_pr_md_resolves_its_object(self):
        self.github.respond(["pr", "list"], stdout="[]")
        (self.work / "pr.md").write_text("T\n")
        (self.work / "pr.md.url").write_text(f"{PR}\n")
        self.assertEqual((7, "legacy"), (lambda t: (t.number, t.via))(self.resolve("pr")))

    def test_issues_never_use_the_pr_context(self):
        self.track("PR_7", PR, "github.com/O/R/pull/7")
        with self.db.write() as db:
            db.execute("INSERT INTO context VALUES (?, 'testuser', 'testrepo', 'main', 'PR_7')",
                       (self.context.toplevel,))
        self.tab("https://github.com/O/R/issues/4")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertEqual(("issue", 4), (lambda t: (t.kind, t.number))(self.resolve("issue")))

    def test_the_browser_tab_is_the_last_fallback_and_says_so(self):
        self.github.respond(["pr", "list"], stdout="[]")
        self.tab(f"{PR}/files")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            target = self.resolve("pr")
        self.assertEqual((7, "browser"), (target.number, target.via))
        instruction = json.loads(stderr.getvalue().splitlines()[-1])
        self.assertEqual(("info", "timvisher_gh_target_from_browser_tab"), (instruction["level"], instruction["code"]))
        self.assertIn(PR, instruction["message"])

    def test_with_no_target_anywhere_it_says_what_to_pass(self):
        self.github.respond(["pr", "list"], stdout="[]")
        for tab in (None, "https://example.com/"):
            if tab:
                self.tab(tab)
            status, instruction = self.refused("pr")
            self.assertEqual((1, "timvisher_gh_target_none"), (status, instruction["code"]), tab)
            self.assertTrue(any("pr.md" in s for s in instruction["suggestions"]))

    def test_comments_and_threads_default_to_the_worktree_pr_only(self):
        self.github.respond(["pr", "list"], stdout=json.dumps([{"number": 9, "state": "OPEN"}]))
        self.assertEqual(("pr", 9), (lambda t: (t.kind, t.number))(self.resolve("comment")))
        self.assertEqual(("pr", 9), (lambda t: (t.kind, t.number))(self.resolve("thread")))

    def test_comments_without_a_worktree_pr_are_an_error_not_a_browser_guess(self):
        self.github.respond(["pr", "list"], stdout="[]")
        self.tab(PR)
        status, instruction = self.refused("comment")
        self.assertEqual((1, "timvisher_gh_target_none"), (status, instruction["code"]))

    def test_a_failing_pr_lookup_is_an_error(self):
        self.github.respond(["pr", "list"], stderr="boom\n", status=1)
        status, instruction = self.refused("pr")
        self.assertEqual((1, "timvisher_gh_gh_failed"), (status, instruction["code"]))


if __name__ == "__main__":
    unittest.main()
