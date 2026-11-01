import json
import os
import pathlib
import tempfile
import time
import unittest
from unittest import mock

from timvisher import tool_log

CLEARED = ("CLAUDE_PID", "CLAUDE_CODE_SESSION_ID", "TIMVISHER_CODEX", "TIMVISHER_AGENT_WRAPPER_EXEC")


class ToolLogTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = pathlib.Path(tmp.name)
        (self.tmp / "sessions").mkdir()
        env = {k: v for k, v in os.environ.items() if k not in CLEARED}
        env["TIMVISHER_TOOL_LOG_DIR"] = str(self.tmp / "logs")
        env["TIMVISHER_TOOL_LOG_SESSIONS_DIR"] = str(self.tmp / "sessions")
        patcher = mock.patch.dict(os.environ, env, clear=True)
        patcher.start()
        self.addCleanup(patcher.stop)

    def lines(self, tool="faketool"):
        path = self.tmp / "logs" / f"{tool}.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()]

    def test_line_has_the_shared_fields(self):
        t0 = time.time()
        tool_log.write("faketool", "/bin/faketool", ["pr", "push"], 3, t0)
        (line,) = self.lines()
        self.assertEqual(line["tool"], "faketool")
        self.assertEqual(line["real"], "/bin/faketool")
        self.assertEqual(line["argv"], ["pr", "push"])
        self.assertEqual(line["rc"], 3)
        self.assertEqual(line["cwd"], os.getcwd())
        self.assertRegex(line["ts"], r"^\d{4}-\d\d-\d\dT[\d:.]+Z$")
        for key in ("epoch", "duration_ms", "host", "caller"):
            self.assertIn(key, line)

    def test_secrets_are_redacted(self):
        self.assertEqual(
            tool_log.redact(["--token", "s3cret", "--password=x", "GH_TOKEN=ghp_abc",
                             "ghp_abcdef", "Authorization: Bearer y", "AKIAABCDEFGHIJKLMNOP",
                             "--name", "ok"]),
            ["--token", "<redacted>", "--password=<redacted>", "GH_TOKEN=<redacted>",
             "<redacted>", "<redacted>", "<redacted>", "--name", "ok"],
        )

    def test_environment_never_reaches_the_log(self):
        with mock.patch.dict(os.environ, {"OPENAI_API_KEY": "sk-resolved-by-op-run"}):
            tool_log.write("faketool", "/bin/faketool", ["x"], 0, time.time())
        text = (self.tmp / "logs" / "faketool.jsonl").read_text()
        self.assertNotIn("sk-resolved-by-op-run", text)
        self.assertNotIn("OPENAI_API_KEY", text)

    def test_caller_from_a_live_claude_session(self):
        pid = os.getpid()
        (self.tmp / "sessions" / f"{pid}.json").write_text(
            json.dumps({"pid": pid, "sessionId": "sess-1", "name": "cfctl-99"}))
        with mock.patch.dict(os.environ, {"CLAUDE_PID": str(pid)}):
            self.assertEqual(tool_log.caller(),
                             {"kind": "claude", "pid": pid, "session_id": "sess-1", "name": "cfctl-99"})

    def test_caller_session_id_only(self):
        with mock.patch.dict(os.environ, {"CLAUDE_CODE_SESSION_ID": "sess-2"}):
            self.assertEqual(tool_log.caller(), {"kind": "claude", "session_id": "sess-2"})

    def test_caller_codex(self):
        with mock.patch.dict(os.environ, {"TIMVISHER_CODEX": "true", "TIMVISHER_AGENT_WRAPPER_EXEC": "4242:codex"}):
            self.assertEqual(tool_log.caller(), {"kind": "codex", "pid": 4242})

    def test_caller_human(self):
        self.assertEqual(tool_log.caller()["kind"], "human")

    def test_log_dir_override_and_default(self):
        self.assertEqual(tool_log.log_dir(), self.tmp / "logs")
        with mock.patch.dict(os.environ, {"TIMVISHER_TOOL_LOG_DIR": ""}):
            default = tool_log.log_dir()
        self.assertTrue(str(default).endswith(("Library/Logs/timvisher/tools", "timvisher/logs")))


if __name__ == "__main__":
    unittest.main()
