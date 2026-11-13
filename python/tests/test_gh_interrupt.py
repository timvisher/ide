import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import time
import unittest

from timvisher.testing import fresh_home

ENTRY = pathlib.Path(__file__).resolve().parents[1] / "bin" / "timvisher_gh"

HANGING_GH = """#!/usr/bin/env bash
: > "$FAKE_GH_STARTED"
exec sleep 60
"""


class InterruptTest(unittest.TestCase):
    def setUp(self):
        home = fresh_home()
        home.__enter__()
        self.addCleanup(home.__exit__, None, None, None)
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = pathlib.Path(tmp.name)
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        gh = bin_dir / "gh"
        gh.write_text(HANGING_GH)
        gh.chmod(0o755)
        self.started = self.tmp / "gh-started"
        self.env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}",
                    "FAKE_GH_STARTED": str(self.started)}

    def test_c_c_while_gh_runs_dies_by_sigint_without_a_traceback(self):
        # timvisher_tests backgrounds suites, so SIGINT arrives ignored, and an ignored SIGINT survives exec.
        proc = subprocess.Popen([sys.executable, str(ENTRY), "-R", "testuser/testrepo", "info", ".me"],
                                cwd=self.tmp, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
        self.addCleanup(proc.kill)
        deadline = time.monotonic() + 10
        while not self.started.exists():
            self.assertLess(time.monotonic(), deadline, "fake gh never started")
            time.sleep(0.05)
        proc.send_signal(signal.SIGINT)
        out, err = proc.communicate(timeout=10)
        self.assertEqual((-signal.SIGINT, ""), (proc.returncode, out))
        self.assertNotIn("Traceback", err)
        self.assertIn("timvisher_gh_interrupted", err)


if __name__ == "__main__":
    unittest.main()
