import contextlib
import cProfile
import datetime
import os
import pathlib
import subprocess
import sys
import time

from timvisher import tool_log

_run = None


def _ms(seconds):
    return round(seconds * 1000)


class Run:
    def __init__(self, argv, profile_dir=None):
        self.argv = list(argv)
        self.epoch = time.time()
        self.started = time.perf_counter()
        self.stack = []
        self.phases = {}
        self.calls = {}
        self.lock = {"n": 0, "wait": 0.0, "held": 0.0, "max_held": 0.0}
        self.profile_dir = profile_dir
        self.profile = None
        self.written = False
        if profile_dir:
            self.profile = cProfile.Profile()
            self.profile.enable()

    def _phase(self, path):
        return self.phases.setdefault(path, {"n": 0, "seconds": 0.0, "calls": {}})

    def call(self, tool, seconds):
        for calls in [self.calls] + [self._phase(path)["calls"] for path in self._paths()]:
            entry = calls.setdefault(tool, {"n": 0, "seconds": 0.0})
            entry["n"] += 1
            entry["seconds"] += seconds

    def _paths(self):
        return ["/".join(self.stack[:i]) for i in range(1, len(self.stack) + 1)]

    def _dump_profile(self):
        self.profile.disable()
        path = pathlib.Path(self.profile_dir) / (
            f"timvisher_gh.{datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H-%M-%S')}"
            f".{os.getpid()}.prof")
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            self.profile.dump_stats(path)
        except OSError as error:
            sys.stderr.write(f"timvisher_gh: could not write the profile '{path}': {error}\n")
            return None
        return str(path)

    def fields(self):
        seconds = time.perf_counter() - self.started
        top = sum(phase["seconds"] for path, phase in self.phases.items() if "/" not in path)

        def calls(entries):
            return {tool: {"n": entry["n"], "ms": _ms(entry["seconds"])} for tool, entry in entries.items()}

        return {"pid": os.getpid(),
                "phases": {path: {"n": phase["n"], "ms": _ms(phase["seconds"]), "calls": calls(phase["calls"])}
                           for path, phase in self.phases.items()},
                "unphased_ms": _ms(seconds - top), "calls": calls(self.calls),
                "lock": {"n": self.lock["n"], "wait_ms": _ms(self.lock["wait"]), "held_ms": _ms(self.lock["held"]),
                         "max_held_ms": _ms(self.lock["max_held"])}}

    # The run's one tool-log line is written here, not in bin/timvisher_gh's
    # finally: cli.main's interrupt path kills the process with SIGINT before
    # that finally would run.
    def finish(self, rc):
        if self.written:
            return
        self.written = True
        fields = self.fields()
        if self.profile is not None:
            fields["profile"] = self._dump_profile()
        real = os.path.realpath(sys.argv[0]) if sys.argv and sys.argv[0] else ""
        tool_log.write("timvisher_gh", real, self.argv, rc, self.epoch, **fields)


def start(argv):
    global _run
    _run = Run(argv, os.environ.get("TIMVISHER_GH_PROFILE") or None)
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
