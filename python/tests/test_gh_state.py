import contextlib
import io
import json
import os
import sqlite3
import subprocess
import sys
import textwrap
import time
import unittest
import unittest.mock

from timvisher.gh import state
from timvisher.gh.errors import Exit
from timvisher.testing import fresh_home

V2 = state.MIGRATIONS + (("ALTER TABLE objects ADD COLUMN extra TEXT",),)

HOLD_LOCK = textwrap.dedent("""
    import sqlite3, sys, time
    db = sqlite3.connect(sys.argv[1], isolation_level=None)
    db.execute("BEGIN IMMEDIATE")
    print("locked", flush=True)
    time.sleep(float(sys.argv[2]))
    db.execute("COMMIT")
""")


class StateTest(unittest.TestCase):
    def setUp(self):
        home = fresh_home()
        home.__enter__()
        self.addCleanup(home.__exit__, None, None, None)
        self.path = state.root() / "state.sqlite3"
        env = {**os.environ, "TIMVISHER_AGENT": "1"}
        patcher = unittest.mock.patch.dict(os.environ, env)
        patcher.start()
        self.addCleanup(patcher.stop)

    def open(self, **kwargs):
        opened = state.open_state(**kwargs)
        self.addCleanup(opened.close)
        return opened

    def refused(self, function):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr), self.assertRaises(Exit) as raised:
            function()
        return raised.exception.status, json.loads(stderr.getvalue().splitlines()[-1])

    def backups(self):
        return sorted(p.name for p in self.path.parent.glob("state.sqlite3.v*.bak"))

    def hold_lock(self, seconds):
        holder = subprocess.Popen([sys.executable, "-c", HOLD_LOCK, str(self.path), str(seconds)],
                                  stdout=subprocess.PIPE, text=True)
        self.addCleanup(holder.stdout.close)
        self.addCleanup(holder.wait)
        self.assertEqual("locked\n", holder.stdout.readline())
        return holder

    def test_a_fresh_state_is_created_under_xdg_data_home_in_wal_mode(self):
        opened = self.open()
        self.assertEqual(self.path, opened.path)
        self.assertTrue(str(self.path).startswith(os.environ["XDG_DATA_HOME"]))
        self.assertEqual("wal", opened.db.execute("PRAGMA journal_mode").fetchone()[0])
        self.assertEqual(1, opened.version())
        self.assertEqual([], self.backups())

    def test_the_schema_is_section_9s(self):
        db = self.open().db
        tables = {row[0]: [c[1] for c in db.execute(f"PRAGMA table_info({row[0]})")]
                  for row in db.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
        self.assertEqual({
            "objects": ["id", "kind", "url", "owner", "repo", "number", "database_id", "parent_id",
                        "store_path", "deleted_at", "fetched_at"],
            "fields": ["object_id", "name", "base", "base_at", "remote", "remote_at"],
            "raw": ["object_id", "payload", "fetched_at"],
            "authored": ["object_id", "path"],
            "context": ["worktree", "owner", "repo", "branch", "pr_id"],
        }, tables)

    def test_foreign_keys_are_enforced(self):
        with self.assertRaises(sqlite3.IntegrityError), self.open().write() as db:
            db.execute("INSERT INTO raw VALUES ('missing', '{}', NULL)")

    def test_reopening_a_current_state_changes_nothing(self):
        self.open().close()
        self.assertEqual(1, self.open().version())
        self.assertEqual([], self.backups())

    def test_a_migration_backs_up_first_then_steps_one_version(self):
        with self.open().write() as db:
            db.execute("INSERT INTO objects (id, kind, url, owner, repo, store_path) "
                       "VALUES ('PR_1', 'pr', 'https://github.com/o/r/pull/1', 'o', 'r', 'github.com/o/r/pull/1')")
        migrated = self.open(migrations=V2)
        self.assertEqual(2, migrated.version())
        self.assertIn("extra", [c[1] for c in migrated.db.execute("PRAGMA table_info(objects)")])
        [backup] = self.backups()
        self.assertRegex(backup, r"^state\.sqlite3\.v1\.\d{4}-\d\d-\d\dT\d\d-\d\d-\d\d\+0000\.bak$")
        old = sqlite3.connect(self.path.parent / backup)
        self.addCleanup(old.close)
        self.assertEqual(1, old.execute("PRAGMA user_version").fetchone()[0])
        self.assertEqual([("PR_1",)], old.execute("SELECT id FROM objects").fetchall())

    def test_a_failed_migration_leaves_the_previous_version(self):
        self.open().close()
        with self.assertRaises(sqlite3.OperationalError):
            state.open_state(migrations=state.MIGRATIONS + (("ALTER TABLE nowhere ADD COLUMN x",),))
        self.assertEqual(1, self.open().version())

    def test_a_too_new_state_is_refused_with_next_steps(self):
        self.path.parent.mkdir(parents=True)
        db = sqlite3.connect(self.path)
        db.execute("PRAGMA user_version = 5")
        db.close()
        status, instruction = self.refused(state.open_state)
        self.assertEqual(1, status)
        self.assertEqual("timvisher_gh_state_too_new", instruction["code"])
        self.assertIn("schema version 5", instruction["message"])
        self.assertTrue(any("git -C ~/git/ide pull" in s for s in instruction["suggestions"]))
        check = sqlite3.connect(self.path)
        self.addCleanup(check.close)
        self.assertEqual(5, check.execute("PRAGMA user_version").fetchone()[0])

    def test_the_busy_timeout_is_10_seconds(self):
        self.assertEqual(10, state.BUSY_TIMEOUT)

    def test_a_writer_that_outlasts_the_busy_timeout_is_a_clear_error(self):
        opened = self.open(busy_timeout=0.3)
        self.hold_lock(3)
        start = time.monotonic()

        def write():
            with opened.write():
                pass

        status, instruction = self.refused(write)
        self.assertLessEqual(0.3, time.monotonic() - start)
        self.assertEqual((1, "timvisher_gh_state_busy"), (status, instruction["code"]))
        self.assertTrue(any("rerun" in s for s in instruction["suggestions"]))

    def test_a_second_writer_waits_for_the_first(self):
        opened = self.open()
        self.hold_lock(0.5)
        start = time.monotonic()
        with opened.write() as db:
            db.execute("INSERT INTO context (worktree) VALUES ('/w')")
        self.assertLessEqual(0.4, time.monotonic() - start)
        self.assertEqual([("/w",)], opened.db.execute("SELECT worktree FROM context").fetchall())

    def test_concurrent_first_opens_migrate_once(self):
        script = "from timvisher.gh import state; state.open_state().close()"
        openers = [subprocess.Popen([sys.executable, "-c", script]) for _ in range(4)]
        self.assertEqual([0, 0, 0, 0], [p.wait() for p in openers])
        self.assertEqual(1, self.open().version())


if __name__ == "__main__":
    unittest.main()
