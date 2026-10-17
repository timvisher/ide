import contextlib
import io
import json
import os
import unittest
from unittest import mock

from timvisher import logging


def agent_env(**extra):
    env = {k: v for k, v in os.environ.items() if k not in ("CLAUDECODE", "TIMVISHER_CODEX")}
    env.update({"TIMVISHER_AGENT": "1", "timvisher_logging_log_level": "TRACE"}, **extra)
    return mock.patch.dict(os.environ, env, clear=True)


class PrintfTest(unittest.TestCase):
    def test_reuses_the_format_for_extra_arguments(self):
        self.assertEqual("a=1 b=2 ", logging.printf("%s=%s ", "a", "1", "b", "2"))

    def test_missing_arguments_are_empty_or_zero(self):
        self.assertEqual("[] [0]", logging.printf("[%s] [%d]"))

    def test_percent_and_backslash_escapes(self):
        self.assertEqual("90%\ttab\\", logging.printf("%s%%\\ttab\\\\", 90))

    def test_a_format_without_specs_prints_once(self):
        self.assertEqual("plain", logging.printf("plain", "ignored", "too"))


class LogTest(unittest.TestCase):
    def emitted(self, function, *args):
        stderr = io.StringIO()
        with agent_env(), contextlib.redirect_stderr(stderr):
            function(*args)
        return [json.loads(line) for line in stderr.getvalue().splitlines()]

    def test_caller_is_the_calling_function(self):
        def reporting_function():
            logging.info("hi")

        (record,) = self.emitted(reporting_function)
        self.assertEqual("reporting_function", record["caller"])

    def test_die_logs_and_raises_system_exit_1(self):
        stderr = io.StringIO()
        with agent_env(), contextlib.redirect_stderr(stderr):
            with self.assertRaises(SystemExit) as raised:
                logging.die("fatal: %s", "boom")
        self.assertEqual(1, raised.exception.code)
        self.assertEqual("DIE", json.loads(stderr.getvalue())["level"])

    def test_f_assert_v_returns_false_for_an_empty_variable(self):
        empty = ""
        stderr = io.StringIO()
        with agent_env(), contextlib.redirect_stderr(stderr):
            self.assertFalse(logging.f_assert_v("empty"))
        self.assertIn("Variable ‘empty’ is empty", stderr.getvalue())
        self.assertEqual("", empty)

    def test_f_assert_v_accepts_falsy_values_that_are_set(self):
        count = 0
        with agent_env():
            self.assertTrue(logging.f_assert_v("count"))
        self.assertEqual(0, count)

    def test_array_v_logs_a_zero_scalar(self):
        items = 0
        stderr = io.StringIO()
        with agent_env(), contextlib.redirect_stderr(stderr):
            logging.info_array_v("items")
        messages = [json.loads(line)["message"] for line in stderr.getvalue().splitlines()]
        self.assertEqual(["item: ‘0’"], messages)
        self.assertEqual(0, items)

    def test_f_assert_v_returns_true_for_a_set_variable(self):
        answer = "42"
        with agent_env():
            self.assertTrue(logging.f_assert_v("answer"))
        self.assertEqual("42", answer)


if __name__ == "__main__":
    unittest.main()
