import contextlib
import io
import json
import os
import pathlib
import tempfile
import unittest
from unittest import mock

from timvisher import aictl

CLEARED = ("TIMVISHER_AGENT", "TIMVISHER_AGENT_NIRMI", "TIMVISHER_AGENT_NIRMI_REASON", "TIMVISHER_AICTL_LOG")


class AictlTest(unittest.TestCase):
    def setUp(self):
        state = tempfile.TemporaryDirectory()
        self.addCleanup(state.cleanup)
        self.state = pathlib.Path(state.name)
        env = {k: v for k, v in os.environ.items() if k not in CLEARED}
        env["XDG_STATE_HOME"] = str(self.state)
        patcher = mock.patch.dict(os.environ, env, clear=True)
        patcher.start()
        self.addCleanup(patcher.stop)

    def emitted(self, function, *args, **kwargs):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            returned = function(*args, **kwargs)
        return returned, [json.loads(line) for line in stderr.getvalue().splitlines()]

    def test_keywords_and_bash_style_arguments_emit_the_same_instruction(self):
        _, by_keyword = self.emitted(
            aictl.info, code="c", message="m", reason="r", doc="d", suggestions=["s1", "s2"], data={"n": 1}
        )
        _, by_flag = self.emitted(
            aictl.info, "--code", "c", "--message", "m", "--reason", "r", "--doc", "d",
            "--suggestion", "s1", "--suggestion", "s2", "--data", '{"n":1}',
        )
        self.assertEqual(by_flag, by_keyword)
        self.assertEqual(
            {"type": "instruction", "level": "info", "code": "c", "message": "m", "reason": "r",
             "data": {"n": 1}, "suggestions": ["s1", "s2"], "doc": "d"},
            by_keyword[0],
        )

    def test_error_returns_false(self):
        returned, (record,) = self.emitted(aictl.error, code="bad", message="It broke")
        self.assertIs(False, returned)
        self.assertEqual(False, record["retryable"])

    def test_die_raises_system_exit_1(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as raised:
            aictl.die(code="bad", message="It broke")
        self.assertEqual(1, raised.exception.code)

    def test_warn_without_a_bypass_raises(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as raised:
            aictl.warn(code="guarded", message="Refusing")
        self.assertEqual(1, raised.exception.code)

    def test_warn_with_nirmi_and_a_reason_bypasses_and_audits(self):
        os.environ.update(TIMVISHER_AGENT_NIRMI="1", TIMVISHER_AGENT_NIRMI_REASON="needed")
        returned, (record,) = self.emitted(aictl.warn, code="guarded", message="Refusing", command="rm x")
        self.assertIsNone(returned)
        self.assertEqual("bypass", record["level"])
        audit = self.state / "timvisher" / "wrappers" / "aictl-bypass" / "log.jsonl"
        entry = json.loads(audit.read_text())
        self.assertEqual(("guarded", "needed", "rm x"), (entry["code"], entry["reason"], entry["command"]))

    def test_the_audit_cwd_is_the_logical_path(self):
        real = self.state / "real"
        real.mkdir()
        link = self.state / "link"
        link.symlink_to(real)
        os.environ.update(TIMVISHER_AGENT_NIRMI="1", TIMVISHER_AGENT_NIRMI_REASON="needed", PWD=str(link))
        here = os.getcwd()
        os.chdir(link)
        self.addCleanup(os.chdir, here)
        self.emitted(aictl.warn, code="guarded", message="Refusing")
        audit = self.state / "timvisher" / "wrappers" / "aictl-bypass" / "log.jsonl"
        self.assertEqual(str(link), json.loads(audit.read_text())["cwd"])

    def test_listening(self):
        self.assertFalse(aictl.listening())
        os.environ["TIMVISHER_AGENT"] = "1"
        self.assertTrue(aictl.listening())


if __name__ == "__main__":
    unittest.main()
