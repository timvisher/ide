import contextlib
import datetime
import os
import pathlib
import sqlite3
import time

from timvisher.gh.errors import fail

BUSY_TIMEOUT = 10

MIGRATIONS = (
    (
        """CREATE TABLE objects(
             id TEXT PRIMARY KEY,
             kind TEXT NOT NULL,
             url TEXT NOT NULL UNIQUE,
             owner TEXT NOT NULL, repo TEXT NOT NULL,
             number INTEGER, database_id INTEGER,
             parent_id TEXT REFERENCES objects(id),
             store_path TEXT NOT NULL,
             deleted_at TEXT, fetched_at TEXT)""",
        """CREATE TABLE fields(
             object_id TEXT REFERENCES objects(id), name TEXT,
             base TEXT, base_at TEXT,
             remote TEXT, remote_at TEXT,
             PRIMARY KEY (object_id, name))""",
        """CREATE TABLE raw(
             object_id TEXT PRIMARY KEY REFERENCES objects(id), payload TEXT, fetched_at TEXT)""",
        """CREATE TABLE authored(
             object_id TEXT REFERENCES objects(id), path TEXT, PRIMARY KEY (object_id, path))""",
        """CREATE TABLE context(
             worktree TEXT PRIMARY KEY, owner TEXT, repo TEXT, branch TEXT,
             pr_id TEXT REFERENCES objects(id))""",
    ),
)


def root():
    data = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
    return pathlib.Path(data) / "timvisher_gh"


def _stamp():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H-%M-%S%z")


def _busy(path, error):
    fail("timvisher_gh_state_busy", f"Another timvisher_gh is writing '{path}'.",
         reason=str(error),
         suggestions=["Wait for the other timvisher_gh command to finish, then rerun this one",
                      f"See what holds it with 'lsof {path}'"])


class State:
    def __init__(self, path, connection):
        self.path = path
        self.db = connection

    @contextlib.contextmanager
    def write(self):
        try:
            self.db.execute("BEGIN IMMEDIATE")
        except sqlite3.OperationalError as error:
            _busy(self.path, error)
        try:
            yield self.db
        except BaseException:
            self.db.execute("ROLLBACK")
            raise
        self.db.execute("COMMIT")

    def version(self):
        return self.db.execute("PRAGMA user_version").fetchone()[0]

    def close(self):
        self.db.close()


def _backup(state, version):
    target = state.path.with_name(f"{state.path.name}.v{version}.{_stamp()}.bak")
    copy = sqlite3.connect(target)
    try:
        state.db.backup(copy)
    finally:
        copy.close()


def _too_new(path, version, known):
    fail("timvisher_gh_state_too_new",
         f"'{path}' is schema version {version}, newer than this timvisher_gh knows ({known}).",
         reason="A newer timvisher_gh wrote it; this one can't read it safely.",
         suggestions=["Update timvisher_gh: 'git -C ~/git/ide pull --ff-only', then rerun",
                      f"Or move '{path}' aside to start a fresh state; the store files are kept"])


def _migrate(state, migrations):
    while True:
        with state.write() as db:
            version = state.version()
            if len(migrations) < version:
                _too_new(state.path, version, len(migrations))
            if version == len(migrations):
                return
        # No backup of a version 0 DB: it holds nothing, and backing it up would
        # leave a .bak behind on every first run.
        if 0 < version:
            _backup(state, version)
        with state.write() as db:
            if state.version() != version:
                continue
            for statement in migrations[version]:
                db.execute(statement)
            db.execute(f"PRAGMA user_version = {version + 1}")


# Switching to WAL takes a lock without waiting on the busy timeout, so it
# is retried here until that timeout runs out.
def _wal(connection, busy_timeout):
    deadline = time.monotonic() + busy_timeout
    while True:
        try:
            if connection.execute("PRAGMA journal_mode = WAL").fetchone()[0] == "wal":
                return
        except sqlite3.OperationalError as error:
            if "locked" not in str(error):
                raise
        if deadline < time.monotonic():
            raise sqlite3.OperationalError("database is locked")
        time.sleep(0.05)


def open_state(path=None, *, migrations=MIGRATIONS, busy_timeout=BUSY_TIMEOUT):
    path = pathlib.Path(path) if path is not None else root() / "state.sqlite3"
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path, timeout=busy_timeout, isolation_level=None)
    state = State(path, connection)
    try:
        _wal(connection, busy_timeout)
        connection.execute("PRAGMA foreign_keys = ON")
        _migrate(state, migrations)
    except sqlite3.OperationalError as error:
        connection.close()
        if "locked" in str(error) or "busy" in str(error):
            _busy(path, error)
        raise
    except BaseException:
        connection.close()
        raise
    return state
