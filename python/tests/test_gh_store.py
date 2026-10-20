import contextlib
import io
import json
import pathlib
import tempfile
import unittest

from timvisher.gh import state, store
from timvisher.gh.errors import Exit
from timvisher.testing import fresh_home

PR = "https://github.com/O/R/pull/7"
PR_KEY = "github.com/O/R/pull/7"
THREAD_KEY = f"{PR_KEY}/threads/2026-10-10T10-01-00+0000-alice-a.go-L4"
REPLY_KEY = f"{THREAD_KEY}/replies/2026-10-10T11-00-00+0000-testuser-ok"


class StoreTest(unittest.TestCase):
    def setUp(self):
        home = fresh_home()
        home.__enter__()
        self.addCleanup(home.__exit__, None, None, None)
        self.state = state.open_state()
        self.addCleanup(self.state.close)
        self.db = self.state.db
        work = tempfile.TemporaryDirectory()
        self.addCleanup(work.cleanup)
        self.work = pathlib.Path(work.name)

    def add_pr(self):
        with self.state.write() as db:
            store.register(db, id="PR_7", kind="pr", url=PR, owner="O", repo="R", number=7, store_path=PR_KEY)

    def add_thread(self):
        self.add_pr()
        with self.state.write() as db:
            store.register(db, id="PRRT_1", kind="thread", url=f"{PR}#discussion_r66", owner="O", repo="R",
                           database_id=66, parent_id="PR_7", store_path=THREAD_KEY)
            store.register(db, id="PRRC_67", kind="comment", url=f"{PR}#discussion_r67", owner="O", repo="R",
                           database_id=67, parent_id="PRRT_1", store_path=REPLY_KEY)

    def test_store_files_by_kind(self):
        self.add_thread()
        self.assertEqual(store.root() / PR_KEY / "pr.md", store.store_file(self.db, "PR_7"))
        self.assertEqual(store.root() / THREAD_KEY / "root-comment.md", store.store_file(self.db, "PRRT_1"))
        self.assertEqual(store.root() / REPLY_KEY / "comment.md", store.store_file(self.db, "PRRC_67"))

    def test_promotion_moves_the_file_and_leaves_a_symlink_recorded_as_authored(self):
        self.add_pr()
        source = self.work / "pr.md"
        source.write_text("Title\n\nBody\n")
        with self.state.write() as db:
            target = store.promote(db, "PR_7", source)
        self.assertEqual("Title\n\nBody\n", target.read_text())
        self.assertTrue(source.is_symlink())
        self.assertEqual(target, source.resolve())
        self.assertEqual([("PR_7", str(source))], self.db.execute("SELECT * FROM authored").fetchall())

    def test_promoting_a_file_already_linked_into_the_store_only_records_it(self):
        self.add_pr()
        target = store.store_file(self.db, "PR_7")
        target.parent.mkdir(parents=True)
        target.write_text("T\n")
        link = self.work / "pr.md"
        link.symlink_to(target)
        with self.state.write() as db:
            store.promote(db, "PR_7", link)
        self.assertEqual("T\n", target.read_text())
        self.assertEqual(1, self.db.execute("SELECT count(*) FROM authored").fetchone()[0])

    def test_promotion_never_overwrites_a_different_store_file(self):
        self.add_pr()
        target = store.store_file(self.db, "PR_7")
        target.parent.mkdir(parents=True)
        target.write_text("store edits\n")
        source = self.work / "pr.md"
        source.write_text("worktree version\n")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr), self.assertRaises(Exit), self.state.write() as db:
            store.promote(db, "PR_7", source)
        self.assertEqual(("store edits\n", "worktree version\n"), (target.read_text(), source.read_text()))
        self.assertFalse(source.is_symlink())
        self.assertIn("timvisher_gh_store_conflict", stderr.getvalue())

    def test_promoting_an_identical_copy_links_it(self):
        self.add_pr()
        target = store.store_file(self.db, "PR_7")
        target.parent.mkdir(parents=True)
        target.write_text("same\n")
        source = self.work / "pr.md"
        source.write_text("same\n")
        with self.state.write() as db:
            store.promote(db, "PR_7", source)
        self.assertEqual(target, source.resolve())

    def test_free_names_never_reuse_an_existing_one(self):
        taken = self.work / "f"
        taken.write_text("1")
        first = store.free(taken)
        first.write_text("2")
        self.assertEqual(("f.adopted", "f.adopted-2"), (first.name, store.free(taken).name))

    def test_backfill_restores_the_store_file_from_the_base_and_the_symlink(self):
        self.add_pr()
        source = self.work / "pr.md"
        source.write_text("x\n")
        with self.state.write() as db:
            target = store.promote(db, "PR_7", source)
            store.set_base(db, "PR_7", "title", "Title", "t0")
            store.set_base(db, "PR_7", "body", "Body", "t0")
        target.unlink()
        source.unlink()
        restored = store.backfill(self.db, "PR_7", fetch=self.fail)
        self.assertEqual([target, source], restored)
        self.assertEqual("Title\n\nBody\n", source.read_text())

    def test_backfill_without_a_base_uses_github(self):
        self.add_thread()
        store.backfill(self.db, "PRRC_67", fetch=lambda: {"body": "from GitHub"})
        self.assertEqual("from GitHub\n", store.store_file(self.db, "PRRC_67").read_text())

    def test_backfill_leaves_present_files_alone(self):
        self.add_pr()
        target = store.store_file(self.db, "PR_7")
        target.parent.mkdir(parents=True)
        target.write_text("edited\n")
        self.assertEqual([], store.backfill(self.db, "PR_7", fetch=self.fail))
        self.assertEqual("edited\n", target.read_text())

    def test_an_upstream_deletion_archives_the_object_and_its_children(self):
        self.add_thread()
        source = self.work / "reply.md"
        source.write_text("ok\n")
        with self.state.write() as db:
            store.promote(db, "PRRC_67", source)
            (store.root() / THREAD_KEY / "root-comment.md").write_text("nit\n")
            archived = store.archive(db, "PRRT_1", "2026-10-11T00-00-00+0000")
        self.assertEqual(store.root() / "archive" / THREAD_KEY, archived)
        self.assertFalse((store.root() / THREAD_KEY).exists())
        self.assertEqual("nit\n", (archived / "root-comment.md").read_text())
        paths = dict(self.db.execute("SELECT id, store_path FROM objects"))
        self.assertEqual((PR_KEY, f"archive/{THREAD_KEY}", f"archive/{REPLY_KEY}"),
                         (paths["PR_7"], paths["PRRT_1"], paths["PRRC_67"]))
        deleted = dict(self.db.execute("SELECT id, deleted_at FROM objects"))
        self.assertEqual(("2026-10-11T00-00-00+0000", None), (deleted["PRRT_1"], deleted["PR_7"]))
        self.assertEqual(store.root() / "archive" / REPLY_KEY / "comment.md", source.resolve())
        self.assertEqual("ok\n", source.read_text())

    def test_archiving_a_parent_after_a_child_merges_into_the_archive(self):
        self.add_thread()
        reply = store.store_file(self.db, "PRRC_67")
        reply.parent.mkdir(parents=True)
        reply.write_text("ok\n")
        (store.root() / THREAD_KEY / "root-comment.md").write_text("nit\n")
        with self.state.write() as db:
            store.archive(db, "PRRC_67", "t1")
        (store.root() / THREAD_KEY / "replies" / "r2").mkdir(parents=True)
        (store.root() / THREAD_KEY / "replies" / "r2" / "comment.md").write_text("two\n")
        with self.state.write() as db:
            store.archive(db, "PRRT_1", "t2")
        archived = store.root() / "archive" / THREAD_KEY
        self.assertEqual(("nit\n", "ok\n", "two\n"),
                         ((archived / "root-comment.md").read_text(),
                          (store.root() / "archive" / REPLY_KEY / "comment.md").read_text(),
                          (archived / "replies" / "r2" / "comment.md").read_text()))
        self.assertFalse((store.root() / THREAD_KEY).exists())
        self.assertEqual(f"archive/{REPLY_KEY}",
                         self.db.execute("SELECT store_path FROM objects WHERE id = 'PRRC_67'").fetchone()[0])

    def test_archiving_matches_children_by_path_not_by_like_wildcards(self):
        self.add_pr()
        with self.state.write() as db:
            store.register(db, id="PR_70", kind="pr", url="https://github.com/O/R/pull/70", owner="O", repo="R",
                           number=70, store_path="github.com/O/R/pull/70")
            store.archive(db, "PR_7", "ts")
        self.assertEqual("github.com/O/R/pull/70",
                         self.db.execute("SELECT store_path FROM objects WHERE id = 'PR_70'").fetchone()[0])

    def test_exports_follow_every_commit_and_skip_a_rolled_back_one(self):
        self.add_thread()
        store.exporting(self.state, lambda object_id: {"schema_version": 1, "id": object_id}, lambda: "TS")
        with self.state.write():
            self.state.touch("PR_7")
            self.state.touch("PRRT_1")
        self.assertEqual({"schema_version": 1, "id": "PR_7"}, json.loads((store.root() / PR_KEY / "pr.json").read_text()))
        self.assertEqual(f"{PR}\n", (store.root() / PR_KEY / "pr.url").read_text())
        self.assertEqual("PRRT_1", json.loads((store.root() / THREAD_KEY / "thread.json").read_text())["id"])
        self.assertEqual(f"{PR}#discussion_r66\n", (store.root() / THREAD_KEY / "thread.url").read_text())
        with self.assertRaises(RuntimeError), self.state.write():
            self.state.touch("PRRC_67")
            raise RuntimeError
        self.assertFalse((store.root() / REPLY_KEY / "comment.json").exists())
        self.assertEqual(set(), self.state.touched)

    def test_a_differing_url_export_is_saved_as_a_bak_before_rewriting(self):
        self.add_pr()
        url = store.root() / PR_KEY / "pr.url"
        url.parent.mkdir(parents=True)
        url.write_text("https://github.com/O/R/pull/8\n")
        store.exporting(self.state, lambda object_id: {}, lambda: "2026-10-11T00-00-00+0000")
        with self.state.write():
            self.state.touch("PR_7")
        self.assertEqual(f"{PR}\n", url.read_text())
        self.assertEqual("https://github.com/O/R/pull/8\n",
                         (url.parent / "pr.url.bak.2026-10-11T00-00-00+0000").read_text())
        with self.state.write():
            self.state.touch("PR_7")
        self.assertEqual(1, len(list(url.parent.glob("pr.url.bak.*"))))

    def fail(self):
        raise AssertionError("fetched from GitHub although a base exists")


if __name__ == "__main__":
    unittest.main()
