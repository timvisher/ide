import json
import os
import pathlib
import subprocess
import tempfile
import unittest
from unittest import mock

from timvisher import browser

RECORD = {
    "schema_version": 1,
    "url": "https://github.com/DataDog/x/pull/7",
    "title": "Fix the thing",
    "browser": "Vivaldi",
}


class BrowserTest(unittest.TestCase):
    def setUp(self):
        bin_dir = tempfile.TemporaryDirectory()
        self.addCleanup(bin_dir.cleanup)
        self.bin = pathlib.Path(bin_dir.name)
        self.calls = self.bin / "calls"
        patcher = mock.patch.dict(os.environ, {"PATH": f"{self.bin}:{os.environ['PATH']}"})
        patcher.start()
        self.addCleanup(patcher.stop)

    def fake_cli(self, stdout="", status=0):
        payload = self.bin / "stdout"
        payload.write_text(stdout)
        script = self.bin / "timvisher_browser"
        script.write_text(
            "#!/usr/bin/env bash\n"
            f"printf '%s\\n' \"$*\" >> '{self.calls}'\n"
            f"cat '{payload}'\n"
            f"exit {status}\n"
        )
        script.chmod(0o755)

    def test_active_tab_returns_the_record(self):
        self.fake_cli(json.dumps(RECORD))
        self.assertEqual(RECORD, browser.active_tab())

    def test_active_tab_pins_the_schema_version(self):
        self.fake_cli(json.dumps(RECORD))
        browser.active_tab()
        self.assertEqual("tab info --schema-version 1\n", self.calls.read_text())

    def test_open_tab_hands_the_url_to_the_cli_and_returns_it(self):
        url = "https://github.com/DataDog/x/pull/8"
        self.fake_cli(url + "\n")
        self.assertEqual(url, browser.open_tab(url))
        self.assertEqual(f"tab {url}\n", self.calls.read_text())

    def test_a_failing_cli_raises(self):
        self.fake_cli(status=1)
        with self.assertRaises(subprocess.CalledProcessError):
            browser.active_tab()


if __name__ == "__main__":
    unittest.main()
