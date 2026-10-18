import importlib.util
import io
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "conformance_run", pathlib.Path(__file__).resolve().parent / "conformance" / "run.py"
)
run = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(run)

DOCUMENT = '''# Title

Prose that is not an example.

### Example 1: info in human format

```env
TIMVISHER_AGENT_NIRMI_REASON=a reason = with equals
```

```call
info 'hello %s' world
```

```stdout
```

```stderr
<TS> INFO main: hello world
```

```status
0
```

### Example 2: a wrong expectation

```call
info 'hello'
```

```stdout
```

```stderr
<TS> INFO main: goodbye
```

```status
0
```
'''


class ParseTest(unittest.TestCase):
    def setUp(self):
        self.examples = run.parse(DOCUMENT)

    def test_finds_each_example_with_its_number_and_title(self):
        self.assertEqual(
            [(1, "info in human format"), (2, "a wrong expectation")],
            [(e.number, e.title) for e in self.examples],
        )

    def test_reads_the_blocks(self):
        blocks = self.examples[0].blocks
        self.assertEqual("info 'hello %s' world\n", blocks["call"])
        self.assertEqual("", blocks["stdout"])
        self.assertEqual("<TS> INFO main: hello world\n", blocks["stderr"])
        self.assertEqual("0\n", blocks["status"])

    def test_env_values_are_literal_after_the_first_equals(self):
        self.assertEqual(
            {"TIMVISHER_AGENT_NIRMI_REASON": "a reason = with equals"}, self.examples[0].env()
        )


class NormalizeTest(unittest.TestCase):
    def test_replaces_timestamps_and_paths(self):
        text = "2026-10-16T23:30:00+0000 INFO main: in /tmp/x/cwd"
        self.assertEqual(
            "<TS> INFO main: in <CWD>", run.normalize(text, [("/tmp/x/cwd", "<CWD>")])
        )

    def test_only_utc_timestamps_are_normalized(self):
        text = "2026-10-16T19:30:00-0400 INFO main: hi"
        self.assertEqual(text, run.normalize(text, []))

    def test_epochs_are_normalized_only_when_asked(self):
        text = '{"ts":1792193053}'
        self.assertEqual(text, run.normalize(text, []))
        self.assertEqual('{"ts":<EPOCH>}', run.normalize(text, [], epoch=True))


class SuiteTest(unittest.TestCase):
    def test_a_matching_example_passes_and_a_wrong_one_fails(self):
        examples = run.parse(DOCUMENT)
        result = unittest.TextTestRunner(stream=io.StringIO(), verbosity=0).run(
            run.suite(examples, {"bash": run.bash_adapter})
        )
        self.assertEqual(2, result.testsRun)
        self.assertEqual(["bash.example_02"], [test.id() for test, _ in result.failures])
        self.assertEqual([], result.errors)

    def test_the_document_has_examples_for_every_adapter(self):
        examples = run.parse(run.DOCUMENT.read_text())
        self.assertLess(0, len(examples))
        self.assertEqual(
            len(examples) * len(run.ADAPTERS), run.suite(examples).countTestCases()
        )


if __name__ == "__main__":
    unittest.main()
