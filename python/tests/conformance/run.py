import dataclasses
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent
DOCUMENT = HERE / "logging-aictl.md"

CLEARED = (
    "TIMVISHER_AGENT",
    "CLAUDECODE",
    "TIMVISHER_CODEX",
    "timvisher_logging_log_level",
    "TIMVISHER_AGENT_NIRMI",
    "TIMVISHER_AGENT_NIRMI_REASON",
    "TIMVISHER_AICTL_LOG",
)
TIMESTAMP = re.compile(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\+0000")
EPOCH = re.compile(r'"ts":\d+')
HEADING = re.compile(r"^### Example (\d+): (.*)$", re.M)
BLOCK = re.compile(r"^```([a-z-]+)\n(.*?)^```$", re.M | re.S)


@dataclasses.dataclass
class Example:
    number: int
    title: str
    blocks: dict

    def env(self):
        pairs = {}
        for line in self.blocks.get("env", "").splitlines():
            name, _, value = line.partition("=")
            pairs[name] = value
        return pairs


@dataclasses.dataclass
class Outcome:
    stdout: str
    stderr: str
    status: str
    aictl_log: str | None
    audit_log: str | None
    created_missing_log: bool


def parse(text):
    headings = list(HEADING.finditer(text))
    examples = []
    for i, heading in enumerate(headings):
        end = headings[i + 1].start() if i + 1 < len(headings) else len(text)
        body = text[heading.end():end]
        blocks = {name: content for name, content in BLOCK.findall(body)}
        examples.append(Example(int(heading.group(1)), heading.group(2), blocks))
    return examples


def normalize(text, paths, epoch=False):
    text = TIMESTAMP.sub("<TS>", text)
    if epoch:
        text = EPOCH.sub('"ts":<EPOCH>', text)
    for path, placeholder in paths:
        text = text.replace(path, placeholder)
    return text


@dataclasses.dataclass
class Run:
    cwd: pathlib.Path
    state: pathlib.Path
    log: pathlib.Path
    missing: pathlib.Path
    fixture: pathlib.Path
    env: dict
    call: str


def prepare(example, workdir, root=ROOT):
    run = Run(
        cwd=workdir / "cwd",
        state=workdir / "state",
        log=workdir / "aictl.log",
        missing=workdir / "missing.log",
        fixture=workdir / "fixture",
        env={k: v for k, v in os.environ.items() if k not in CLEARED},
        call="",
    )
    run.cwd.mkdir()
    run.state.mkdir()
    run.env["XDG_STATE_HOME"] = str(run.state)
    run.env["PATH"] = f"{root / 'bash' / 'bin'}:{run.env.get('PATH', '')}"
    substitutions = {"<AICTL_LOG>": str(run.log), "<AICTL_LOG_MISSING>": str(run.missing)}
    for name, value in example.env().items():
        if value == "<AICTL_LOG>":
            run.log.touch()
        run.env[name] = substitutions.get(value, value)
    if "fixture" in example.blocks:
        run.fixture.write_text(example.blocks["fixture"])
    run.call = example.blocks["call"].strip("\n").replace("<FIXTURE>", str(run.fixture))
    return run


def outcome(run, result):
    paths = [(str(run.fixture), "<FIXTURE>"), (str(run.cwd), "<CWD>"), (str(run.log), "<AICTL_LOG>")]
    audit = run.state / "timvisher" / "wrappers" / "aictl-bypass" / "log.jsonl"
    return Outcome(
        stdout=normalize(result.stdout.decode(), paths),
        stderr=normalize(result.stderr.decode(), paths),
        status=str(result.returncode),
        aictl_log=normalize(run.log.read_bytes().decode(), paths) if run.log.exists() else None,
        audit_log=normalize(audit.read_bytes().decode(), paths, epoch=True) if audit.exists() else None,
        created_missing_log=run.missing.exists(),
    )


def bash_adapter(example, workdir, root=ROOT):
    run = prepare(example, workdir, root)
    script = "".join(
        [
            f"source '{root / 'bash' / 'functions' / 'logging.bash'}'\n",
            f"source '{root / 'bash' / 'functions' / 'aictl.bash'}'\n",
            example.blocks.get("vars", ""),
            run.call,
            "\n",
        ]
    )
    result = subprocess.run(
        ["bash", "-c", script],
        input=example.blocks.get("stdin", "").encode(),
        capture_output=True,
        env=run.env,
        cwd=run.cwd,
    )
    return outcome(run, result)


PYTHON_CALL = """
import importlib
import json
import sys

spec = json.loads(sys.argv[1])
falsy_returns = set(spec["falsy_returns"])
sys.path.insert(0, spec["lib"])
namespace = dict(spec["vars"])
namespace["__name__"] = "__main__"
namespace["_function"] = getattr(importlib.import_module(spec["module"]), spec["function"])
namespace["_args"] = spec["args"]
try:
    exec("_returned = _function(*_args)", namespace)
    status = 1 if namespace["_returned"] is False and spec["function"] in falsy_returns else 0
except SystemExit as exit:
    status = exit.code if isinstance(exit.code, int) else 1
sys.stdout.flush()
sys.stderr.flush()
sys.exit(status)
"""


def _bash_words(script, run, *args):
    result = subprocess.run(
        ["bash", "-c", script, "_", *args], capture_output=True, env=run.env, cwd=run.cwd, check=True
    )
    return result.stdout.decode().split("\0")[:-1]


FALSY_RETURNS = {"error", "f_assert_v", "listening"}


def python_adapter(example, workdir, root=ROOT):
    run = prepare(example, workdir, root)
    assignments = example.blocks.get("vars", "")
    words = _bash_words(assignments + 'eval "set -- $1"; printf "%s\\0" "$@"', run, run.call)
    if words[0] == "aictl":
        module, words = "timvisher.aictl", words[1:]
    elif words[0].startswith("aictl_"):
        module, words = "timvisher.aictl", [words[0][len("aictl_"):], *words[1:]]
    else:
        module = "timvisher.logging"
    variables = {}
    for line in assignments.splitlines():
        name, _, value = line.partition("=")
        values = _bash_words(
            assignments + f'(( ${{#{name}[@]}} )) && printf "%s\\0" "${{{name}[@]}}"; true', run
        )
        variables[name] = values if value.startswith("(") else (values[0] if values else "")
    spec = {
        "lib": str(root / "python" / "lib"),
        "module": module,
        "function": words[0],
        "args": words[1:],
        "vars": variables,
        "falsy_returns": sorted(FALSY_RETURNS),
    }
    result = subprocess.run(
        [sys.executable, "-c", PYTHON_CALL, json.dumps(spec)],
        input=example.blocks.get("stdin", "").encode(),
        capture_output=True,
        env=run.env,
        cwd=run.cwd,
    )
    return outcome(run, result)


ADAPTERS = {"bash": bash_adapter, "python": python_adapter}


class ExampleCase(unittest.TestCase):
    def __init__(self, adapter_name, adapter, example):
        super().__init__("runTest")
        self.adapter_name = adapter_name
        self.adapter = adapter
        self.example = example

    def id(self):
        return f"{self.adapter_name}.example_{self.example.number:02d}"

    def __str__(self):
        return f"{self.id()}: {self.example.title}"

    def runTest(self):
        blocks = self.example.blocks
        with tempfile.TemporaryDirectory() as workdir:
            outcome = self.adapter(self.example, pathlib.Path(os.path.realpath(workdir)))
        self.assertEqual(blocks.get("stdout", ""), outcome.stdout, "stdout")
        self.assertEqual(blocks.get("stderr", ""), outcome.stderr, "stderr")
        self.assertEqual(blocks.get("status", "0\n").strip(), outcome.status, "status")
        if "aictl-log" in blocks:
            self.assertEqual(blocks["aictl-log"], outcome.aictl_log, "aictl-log")
        self.assertEqual(blocks.get("audit-log"), outcome.audit_log, "audit-log")
        self.assertFalse(outcome.created_missing_log, "<AICTL_LOG_MISSING> was created")


def suite(examples, adapters=None):
    tests = unittest.TestSuite()
    for name, adapter in (adapters or ADAPTERS).items():
        for example in examples:
            tests.addTest(ExampleCase(name, adapter, example))
    return tests


def main():
    examples = parse(DOCUMENT.read_text())
    result = unittest.TextTestRunner(stream=sys.stdout, verbosity=2).run(suite(examples))
    return 0 if result.wasSuccessful() and result.testsRun else 1


if __name__ == "__main__":
    sys.exit(main())
