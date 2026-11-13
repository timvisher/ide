import contextlib
import datetime
import json
import os
import pathlib
import re
import socket
import subprocess
import sys
import time

_run = None


def log_dir():
    if os.environ.get("TIMVISHER_TOOL_LOG_DIR"):
        return pathlib.Path(os.environ["TIMVISHER_TOOL_LOG_DIR"])
    if sys.platform == "darwin":
        return pathlib.Path.home() / "Library" / "Logs" / "timvisher" / "tools"
    state = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return pathlib.Path(state) / "timvisher" / "logs"


# The same caller object bash/functions/tool_log.bash logs for the gh
# shim, so a run and its gh calls match on it.
def caller():
    pid = os.environ.get("CLAUDE_PID", "")
    if pid.isdigit():
        sessions = pathlib.Path(os.environ.get("TIMVISHER_TOOL_LOG_SESSIONS_DIR")
                                or pathlib.Path.home() / ".claude" / "sessions")
        try:
            os.kill(int(pid), 0)
            content = (sessions / f"{pid}.json").read_text()
        except (OSError, ValueError):
            content = None
        if content is not None:
            session_id = re.search(r'"sessionId":"([^"]*)"', content)
            name = re.search(r'"name":"([^"]*)"', content)
            return {"kind": "claude", "pid": int(pid), "session_id": session_id[1] if session_id else "",
                    "name": name[1] if name else ""}
    if os.environ.get("CLAUDE_CODE_SESSION_ID"):
        return {"kind": "claude", "session_id": os.environ["CLAUDE_CODE_SESSION_ID"]}
    if os.environ.get("TIMVISHER_TOOL_LOG_CALLER_SESSION"):
        return {"kind": "claude", "session_id": os.environ["TIMVISHER_TOOL_LOG_CALLER_SESSION"],
                "name": os.environ.get("TIMVISHER_TOOL_LOG_CALLER_NAME", ""), "forwarded": True}
    if os.environ.get("TIMVISHER_CODEX"):
        pid = os.environ.get("TIMVISHER_AGENT_WRAPPER_EXEC", "").split(":")[0]
        return {"kind": "codex", "pid": int(pid) if pid.isdigit() else None}
    try:
        tty = os.ttyname(0).removeprefix("/dev/")
    except OSError:
        tty = "none"
    return {"kind": "human", "tty": tty}


def _ms(seconds):
    return round(seconds * 1000)


class Run:
    def __init__(self, argv):
        self.argv = list(argv)
        self.cwd = os.getcwd()
        self.epoch = time.time()
        self.started = time.perf_counter()
        self.stack = []
        self.phases = {}
        self.calls = {}
        self.lock = {"n": 0, "wait": 0.0, "held": 0.0, "max_held": 0.0}
        self.written = False

    def _phase(self, path):
        return self.phases.setdefault(path, {"n": 0, "seconds": 0.0, "calls": {}})

    def call(self, tool, seconds):
        for calls in [self.calls] + [self._phase(path)["calls"] for path in self._paths()]:
            entry = calls.setdefault(tool, {"n": 0, "seconds": 0.0})
            entry["n"] += 1
            entry["seconds"] += seconds

    def _paths(self):
        return ["/".join(self.stack[:i]) for i in range(1, len(self.stack) + 1)]

    def line(self, rc):
        seconds = time.perf_counter() - self.started
        top = sum(phase["seconds"] for path, phase in self.phases.items() if "/" not in path)

        def calls(entries):
            return {tool: {"n": entry["n"], "ms": _ms(entry["seconds"])} for tool, entry in entries.items()}

        stamp = datetime.datetime.fromtimestamp(self.epoch, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")
        return {"ts": stamp[:23] + "Z", "epoch": round(self.epoch, 6), "tool": "timvisher_gh",
                "real": os.path.realpath(sys.argv[0]) if sys.argv and sys.argv[0] else "", "argv": self.argv,
                "cwd": self.cwd, "rc": rc, "duration_ms": _ms(seconds), "host": socket.gethostname().split(".")[0],
                "caller": caller(), "pid": os.getpid(),
                "phases": {path: {"n": phase["n"], "ms": _ms(phase["seconds"]), "calls": calls(phase["calls"])}
                           for path, phase in self.phases.items()},
                "unphased_ms": _ms(seconds - top), "calls": calls(self.calls),
                "lock": {"n": self.lock["n"], "wait_ms": _ms(self.lock["wait"]), "held_ms": _ms(self.lock["held"]),
                         "max_held_ms": _ms(self.lock["max_held"])}}

    def finish(self, rc):
        if self.written:
            return
        self.written = True
        line = self.line(rc)
        path = log_dir() / "timvisher_gh.jsonl"
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("a", encoding="utf-8") as log:
                log.write(json.dumps(line, ensure_ascii=False, separators=(",", ":")) + "\n")
        except OSError as error:
            sys.stderr.write(f"timvisher_gh: could not append to '{path}': {error}\n")


def start(argv):
    global _run
    _run = Run(argv)
    return _run


def finish(rc):
    if _run is not None:
        _run.finish(rc)


@contextlib.contextmanager
def phase(name):
    if _run is None:
        yield
        return
    _run.stack.append(name)
    path = "/".join(_run.stack)
    began = time.perf_counter()
    try:
        yield
    finally:
        entry = _run._phase(path)
        entry["n"] += 1
        entry["seconds"] += time.perf_counter() - began
        _run.stack.pop()


def run(args, *rest, **options):
    began = time.perf_counter()
    try:
        return subprocess.run(args, *rest, **options)
    finally:
        if _run is not None:
            _run.call(os.path.basename(str(args[0])), time.perf_counter() - began)


def locked(asked, taken, released):
    if _run is None:
        return
    held = released - taken
    _run.lock["n"] += 1
    _run.lock["wait"] += taken - asked
    _run.lock["held"] += held
    _run.lock["max_held"] = max(_run.lock["max_held"], held)
