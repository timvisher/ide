import contextlib
import io
import json
import os
import unittest
from unittest import mock

from support.case import GhTestCase
from timvisher.gh import adopt, state, store
from timvisher.gh.errors import Exit

PR = "https://github.com/O/R/pull/7"
PR_KEY = "github.com/O/R/pull/7"
NOW = "2026-10-12T00:00:00Z"


class AdoptTest(GhTestCase):
    def setUp(self):
        super().setUp()
        patcher = mock.patch.dict(os.environ, {**self.env(), "TIMVISHER_AGENT": "1"})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.state = state.open_state()
        self.addCleanup(self.state.close)
        store.exporting(self.state, lambda object_id: {"id": object_id}, lambda: "TS")
        self.lookups = []
        self.facts = {"pr": {"id": "PR_7"}, "issue": {"id": "I_3"}}

    def lookup(self, target):
        self.lookups.append(target.url)
        return self.facts[target.kind] if target.kind in ("pr", "issue") else self.facts[target.url]

    def write(self, relative, text):
        path = self.work / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def rows(self, sql, *args):
        return self.state.db.execute(sql, args).fetchall()

    def test_a_root_pr_md_and_url_move_into_the_store_and_leave_symlinks(self):
        self.write("pr.md", "Title\n\nBody\n")
        self.write("pr.md.url", f"{PR}\n")
        self.assertEqual("PR_7", adopt.adopt_root(self.state, self.work, self.lookup, NOW))
        pr_dir = store.root() / PR_KEY
        self.assertEqual("Title\n\nBody\n", (pr_dir / "pr.md").read_text())
        self.assertEqual((pr_dir / "pr.md").resolve(), (self.work / "pr.md").resolve())
        self.assertEqual(f"{PR}\n", (self.work / "pr.md.url").read_text())
        self.assertEqual(pr_dir.resolve(), (self.work / ".timvisher_gh" / "pr").resolve())
        self.assertEqual([(str(self.work), "O", "R", "main", "PR_7")], self.rows("SELECT * FROM context"))
        self.assertEqual([("PR_7", str(self.work / "pr.md"))], self.rows("SELECT * FROM authored"))
        self.assertEqual([("PR_7", "pr", PR, PR_KEY)], self.rows("SELECT id, kind, url, store_path FROM objects"))

    def test_rerunning_root_adoption_changes_nothing(self):
        self.write("pr.md", "T\n")
        self.write("pr.md.url", f"{PR}\n")
        adopt.adopt_root(self.state, self.work, self.lookup, NOW)
        adopt.adopt_root(self.state, self.work, self.lookup, NOW)
        self.assertEqual([PR], self.lookups)
        self.assertEqual("T\n", (self.work / "pr.md").read_text())

    def test_a_root_issue_md_and_url_are_adopted_without_a_worktree_context(self):
        self.write("issue.md", "Bug\n")
        self.write("issue.md.url", "https://github.com/O/R/issues/3\n")
        adopt.adopt_root(self.state, self.work, self.lookup, NOW)
        self.assertEqual("Bug\n", (store.root() / "github.com/O/R/issues/3/issue.md").read_text())
        self.assertTrue((self.work / "issue.md").is_symlink())
        self.assertEqual([], self.rows("SELECT * FROM context"))

    def test_x_merged_records_the_prs_observed_merged_state_then_goes(self):
        self.write("pr.md", "T\n")
        self.write("pr.md.url", f"{PR}\n")
        self.write("x.merged", "")
        adopt.adopt_root(self.state, self.work, self.lookup, NOW)
        self.assertFalse(os.path.lexists(self.work / "x.merged"))
        self.assertEqual([("state", '"merged"')], self.rows("SELECT name, remote FROM fields"))

    def bash_pr_directory(self):
        base = ".timvisher_gh/pr"
        self.write(f"{base}/pr.md", "Title\n\nBody\n")
        self.write(f"{base}/pr.json", json.dumps({"url": PR, "posted": {"title": "Title", "body": "Old body"}}))
        self.write(f"{base}/pr.url", f"{PR}\n")
        self.write(f"{base}/merged", "")
        comments = f"{base}/comments"
        self.write(f"{comments}/2026-10-10T10-00-00+0000-alice-hi.md", "hi there\n")
        self.write(f"{comments}/2026-10-10T10-00-00+0000-alice-hi.md.json", json.dumps({
            "kind": "issue_comment", "id": "IC_1", "database_id": 1, "url": f"{PR}#issuecomment-1",
            "author": "alice", "created_at": "2026-10-10T10:00:00Z", "posted": {"body": "hi there",
                                                                                 "reactions": ["+1"]}}))
        thread = f"{comments}/2026-10-10T11-00-00+0000-bob-a.go-L4-thread"
        self.write(f"{thread}/2026-10-10T11-00-00+0000-bob-nit.md", "nit\n")
        self.write(f"{thread}/2026-10-10T11-00-00+0000-bob-nit.md.json", json.dumps({
            "kind": "review_comment", "id": "PRRC_66", "database_id": 66, "url": f"{PR}#discussion_r66",
            "author": "bob", "created_at": "2026-10-10T11:00:00Z", "thread_id": "PRRT_1", "path": "a.go",
            "line": 4, "posted": {"resolved": True, "reactions": []}}))
        self.write(f"{thread}/2026-10-10T12-00-00+0000-testuser-ok.md", "ok\n")
        self.write(f"{thread}/2026-10-10T12-00-00+0000-testuser-ok.md.json", json.dumps({
            "kind": "review_comment", "id": "PRRC_67", "database_id": 67, "url": f"{PR}#discussion_r67",
            "author": "testuser", "created_at": "2026-10-10T12:00:00Z", "thread_id": "PRRT_1",
            "in_reply_to": 66, "posted": {"body": "ok", "reactions": []}}))
        self.write(f"{comments}/2026-10-10T13-00-00+0000-carol-review.md", "LGTM\n")
        self.write(f"{comments}/2026-10-10T13-00-00+0000-carol-review.md.json", json.dumps({
            "kind": "review", "id": "PRR_9", "database_id": 9, "url": f"{PR}#pullrequestreview-9",
            "author": "carol", "created_at": "2026-10-10T13:00:00Z", "posted": {"reactions": []}}))
        self.write(f"{comments}/draft.md", "not posted yet\n")
        for name, target in (("pr.md", f"{base}/pr.md"), ("pr.md.url", f"{base}/pr.url"),
                             ("x.merged", f"{base}/merged")):
            (self.work / name).symlink_to(target)

    def test_a_bash_pr_directory_is_adopted_into_the_store(self):
        self.bash_pr_directory()
        self.assertEqual("PR_7", adopt.adopt_directory(self.state, self.work, "pr", self.lookup, NOW))
        pr_dir = store.root() / PR_KEY
        link = self.work / ".timvisher_gh" / "pr"
        self.assertTrue(link.is_symlink())
        self.assertEqual(pr_dir.resolve(), link.resolve())
        self.assertEqual("Title\n\nBody\n", (self.work / "pr.md").read_text())
        self.assertEqual(f"{PR}\n", (self.work / "pr.md.url").read_text())
        self.assertFalse(os.path.lexists(self.work / "x.merged"))

        bases = dict(((i, n), json.loads(b)) for i, n, b in
                     self.rows("SELECT object_id, name, base FROM fields WHERE base IS NOT NULL"))
        self.assertEqual({("PR_7", "title"): "Title", ("PR_7", "body"): "Old body", ("IC_1", "body"): "hi there",
                          ("PRRC_67", "body"): "ok"}, bases)
        remotes = dict(((i, n), json.loads(r)) for i, n, r in
                       self.rows("SELECT object_id, name, remote FROM fields WHERE remote IS NOT NULL"))
        self.assertEqual((True, ["+1"], "merged"),
                         (remotes[("PRRT_1", "resolved")], remotes[("IC_1", "reactions")], remotes[("PR_7", "state")]))

        objects = {i: (k, p, s) for i, k, p, s in self.rows("SELECT id, kind, parent_id, store_path FROM objects")}
        thread_key = f"{PR_KEY}/threads/2026-10-10T11-00-00+0000-bob-a.go-L4"
        self.assertEqual({
            "PR_7": ("pr", None, PR_KEY),
            "IC_1": ("comment", "PR_7", f"{PR_KEY}/comments/2026-10-10T10-00-00+0000-alice-hi there"),
            "PRRT_1": ("thread", "PR_7", thread_key),
            "PRRC_67": ("comment", "PRRT_1", f"{thread_key}/replies/2026-10-10T12-00-00+0000-testuser-ok"),
            "PRR_9": ("review", "PR_7", f"{PR_KEY}/reviews/2026-10-10T13-00-00+0000-carol-review"),
        }, objects)
        self.assertEqual("nit\n", (store.root() / thread_key / "root-comment.md").read_text())
        self.assertEqual("ok\n", (store.root() / objects["PRRC_67"][2] / "comment.md").read_text())
        self.assertEqual("LGTM\n", (store.root() / objects["PRR_9"][2] / "review.md").read_text())
        self.assertEqual("not posted yet\n", (pr_dir / "comments" / "draft.md").read_text())
        self.assertEqual([], list(pr_dir.rglob("*.md.json")))
        self.assertEqual([(str(self.work), "O", "R", "main", "PR_7")], self.rows("SELECT * FROM context"))
        self.assertEqual({"id": "PRRT_1"}, json.loads((store.root() / thread_key / "thread.json").read_text()))

    def test_comments_with_the_same_name_in_one_adoption_get_their_own_directories(self):
        base = ".timvisher_gh/pr"
        self.write(f"{base}/pr.json", json.dumps({"url": PR}))
        for n, body in ((1, "LGTM"), (2, "LGTM")):
            self.write(f"{base}/comments/c{n}.md", f"{body} {n}\n")
            self.write(f"{base}/comments/c{n}.md.json", json.dumps({
                "kind": "issue_comment", "id": f"IC_{n}", "database_id": n, "url": f"{PR}#issuecomment-{n}",
                "author": "alice", "created_at": "2026-10-10T10:00:00Z", "posted": {"body": body}}))
        adopt.adopt_directory(self.state, self.work, "pr", self.lookup, NOW)
        paths = dict(self.rows("SELECT id, store_path FROM objects WHERE kind = 'comment'"))
        self.assertNotEqual(paths["IC_1"], paths["IC_2"])
        self.assertEqual(("LGTM 1\n", "LGTM 2\n"), tuple((store.root() / paths[i] / "comment.md").read_text()
                                                         for i in ("IC_1", "IC_2")))

    def test_a_second_adoption_of_the_same_pr_keeps_both_copies(self):
        self.bash_pr_directory()
        adopt.adopt_directory(self.state, self.work, "pr", self.lookup, NOW)
        other = self.tmp / "other"
        (other / ".timvisher_gh/pr/comments").mkdir(parents=True)
        (other / ".timvisher_gh/pr/pr.json").write_text(json.dumps({"url": PR}))
        (other / ".timvisher_gh/pr/pr.md").write_text("Other title\n")
        (other / ".timvisher_gh/pr/comments/draft.md").write_text("other draft\n")
        adopt.adopt_directory(self.state, other, "pr", self.lookup, NOW)
        pr_dir = store.root() / PR_KEY
        self.assertEqual(("Title\n\nBody\n", "Other title\n"),
                         ((pr_dir / "pr.md").read_text(), (pr_dir / "pr.md.adopted").read_text()))
        self.assertEqual(("not posted yet\n", "other draft\n"),
                         ((pr_dir / "comments/draft.md").read_text(),
                          (pr_dir / "comments/draft.md.adopted").read_text()))

    def test_x_merged_stays_when_there_is_no_pr_to_record_it_on(self):
        self.write("x.merged", "")
        adopt.adopt_root(self.state, self.work, self.lookup, NOW)
        self.assertTrue((self.work / "x.merged").exists())

    def test_a_bash_pr_directory_is_adopted_once(self):
        self.bash_pr_directory()
        adopt.adopt_directory(self.state, self.work, "pr", self.lookup, NOW)
        self.assertIsNone(adopt.adopt_directory(self.state, self.work, "pr", self.lookup, NOW))
        self.assertEqual([PR], self.lookups)

    def test_a_bash_issue_directory_is_adopted_into_the_store(self):
        base = ".timvisher_gh/issue"
        issue = "https://github.com/O/R/issues/3"
        self.write(f"{base}/issue.md", "Bug\n\nIt breaks\n")
        self.write(f"{base}/issue.json", json.dumps({"url": issue, "posted": {"title": "Bug", "body": "It broke"}}))
        self.write(f"{base}/issue.url", f"{issue}\n")
        self.assertEqual("I_3", adopt.adopt_directory(self.state, self.work, "issue", self.lookup, NOW))
        issue_dir = store.root() / "github.com/O/R/issues/3"
        link = self.work / ".timvisher_gh" / "issue"
        self.assertTrue(link.is_symlink())
        self.assertEqual(issue_dir.resolve(), link.resolve())
        self.assertEqual("Bug\n\nIt breaks\n", (issue_dir / "issue.md").read_text())
        self.assertEqual({("title", '"Bug"'), ("body", '"It broke"')},
                         set(self.rows("SELECT name, base FROM fields WHERE object_id = 'I_3'")))
        self.assertEqual([], self.rows("SELECT * FROM context"))
        self.assertIsNone(adopt.adopt_directory(self.state, self.work, "issue", self.lookup, NOW))

    def test_a_legacy_comment_file_and_url_are_adopted(self):
        self.facts[f"{PR}#issuecomment-5"] = {"id": "IC_5", "database_id": 5, "kind": "issue_comment",
                                             "author": "testuser", "created_at": "2026-10-10T10:00:00Z",
                                             "body": "hello"}
        source = self.write("reply.md", "hello\n")
        self.write("reply.md.url", f"{PR}#issuecomment-5\n")
        self.assertEqual("IC_5", adopt.adopt_comment(self.state, source, self.lookup, NOW))
        target = store.root() / PR_KEY / "comments/2026-10-10T10-00-00+0000-testuser-hello/comment.md"
        self.assertEqual(target, source.resolve())
        self.assertEqual(target.parent / "comment.url", (self.work / "reply.md.url").resolve())
        self.assertEqual(f"{PR}#issuecomment-5\n", (self.work / "reply.md.url").read_text())
        self.assertEqual([("IC_5", str(source))], self.rows("SELECT * FROM authored"))

    def test_a_sidecar_json_reply_registers_its_thread_and_posted_body(self):
        self.facts[f"{PR}#discussion_r67"] = {
            "id": "PRRC_67", "database_id": 67, "kind": "review_comment", "author": "testuser",
            "created_at": "2026-10-10T12:00:00Z", "body": "ok", "thread_id": "PRRT_1", "in_reply_to": 66,
            "thread": {"thread_id": "PRRT_1", "id": "PRRC_66", "database_id": 66, "url": f"{PR}#discussion_r66",
                       "author": "bob", "created_at": "2026-10-10T11:00:00Z", "path": "a.go", "line": 4}}
        source = self.write("ok.md", "ok\n")
        self.write("ok.md.json", json.dumps({"kind": "review_comment", "database_id": 67,
                                             "url": f"{PR}#discussion_r67", "posted": {"body": "ok"}}))
        adopt.adopt_comment(self.state, source, self.lookup, NOW)
        kinds = dict(self.rows("SELECT id, parent_id FROM objects"))
        self.assertEqual({"PR_7": None, "PRRT_1": "PR_7", "PRRC_67": "PRRT_1"}, kinds)
        self.assertEqual([("PRRC_67", "body", '"ok"')], self.rows("SELECT object_id, name, base FROM fields"))
        self.assertTrue((self.work / "ok.md.json").is_symlink())
        self.assertEqual({"id": "PRRC_67"}, json.loads((self.work / "ok.md.json").read_text()))

    def test_a_sidecar_that_does_not_name_a_comment_is_an_error(self):
        source = self.write("x.md", "x\n")
        self.write("x.md.url", f"{PR}\n")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr), self.assertRaises(Exit) as raised:
            adopt.adopt_comment(self.state, source, self.lookup, NOW)
        self.assertEqual(2, raised.exception.status)
        self.assertEqual("timvisher_gh_adopt_not_a_comment", json.loads(stderr.getvalue().splitlines()[-1])["code"])
        self.assertTrue(source.is_file() and not source.is_symlink())


if __name__ == "__main__":
    unittest.main()
