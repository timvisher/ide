# Logging and aictl conformance

This document is test data. It fixes the behavior of the bash logging
and aictl libraries (`bash/functions/logging.bash`,
`bash/functions/aictl.bash`, and the `aictl` CLI) as examples, so that
the Python implementations (`timvisher.logging`, `timvisher.aictl`)
can be checked against the same behavior by
`python/tests/conformance/run.py`. Every expected output below was
produced by running the bash code.

## The logging functions

`die`, `info`, `warn`, `trace` and `error` format their arguments
`printf`-style and log one line to stderr.

- Without `TIMVISHER_AGENT`, a line is `<timestamp> <LEVEL> <caller>:
  <message>`, the timestamp in UTC as `%FT%T%z`.
- With `TIMVISHER_AGENT` set, a line is compact JSON:
  `{"type":"log","level":…,"caller":…,"message":…}`, as `jq -c`
  writes it (the examples assume `jq` is installed).
- `<caller>` is the function that called the logging function, or
  `main` at the top level. Every example calls from the top level, so
  the plain functions report `main` and each variant reports the
  function that logged for it: `info_v` itself, `info_array` for
  `info_array_v`, `trace_v` for the copy `info_stdout` traces, and so
  on.
- `die` logs at level `DIE` and exits 1.

Which levels log depends on `timvisher_logging_log_level` (`ERROR`,
`WARN`, `INFO`, `TRACE`; `DIE` ranks with `ERROR`):

- set to a known level: that level and the ones above it log;
- set to anything else: everything logs;
- unset, with any of `CLAUDECODE`, `TIMVISHER_CODEX` or
  `TIMVISHER_AGENT` set: only `ERROR` and `DIE` log;
- unset otherwise: everything logs.

Throughout, a variable that is set but empty counts as unset.

The variants build on these: `info_v`, `error_v` and `trace_v` log a
variable's name and value; `f_assert_v` fails when a variable is empty;
`info_array`, `trace_array` and `error_array` log each argument, through
the first argument when it contains `%s`; the `_array_v` variants log
each element of an array variable; `info_stdout` and `error_stdout`
log stdin line by line, numbered, and then print it to stdout (through
`printf`, so `%` and `\` in it are interpreted, and an unterminated
last line is dropped);
`display_script` logs a file's numbered lines.

## The aictl functions

`aictl_die`, `aictl_error`, `aictl_info`, `aictl_notice` and
`aictl_warn` emit one instruction. With `TIMVISHER_AGENT` set it is
compact JSON on stderr; otherwise stderr gets the same fields as text:
`<timestamp> <LEVEL> <code>: <message>` (`ERROR`, `WARN`, `INFO` or
`BYPASS`; the `: <message>` is left out when the message is empty), then
`  reason: `, one `  suggestion: ` per suggestion and `  doc: ` lines,
with `--data` left out. The JSON is also appended to the file named by
`TIMVISHER_AICTL_LOG` when that file exists, whoever reads stderr. They take `--code`,
`--message`, `--reason`, `--doc`, `--command`, `--data` and repeated
`--suggestion`, or positionally a code, a message and suggestions.

- `aictl_die` (level `error`, `retryable` false) exits 1; `aictl_error`
  emits the same and returns 1.
- `aictl_info` (level `info`, no `retryable`) returns 0.
- `aictl_notice` (level `warning`, no `retryable`) returns 0.
- `aictl_warn` (level `warning`, `retryable` true) exits 1, unless
  `TIMVISHER_AGENT_NIRMI` and `TIMVISHER_AGENT_NIRMI_REASON` are both
  set: then it emits a `bypass` instruction, appends an audit line to
  `${XDG_STATE_HOME}/timvisher/wrappers/aictl-bypass/log.jsonl`, and
  returns 0. `TIMVISHER_AGENT_NIRMI` alone is refused with
  `aictl_bypass_missing_reason`.
- `aictl_listening` succeeds when `TIMVISHER_AGENT` or
  `TIMVISHER_AICTL_LOG` is set.

The `aictl` CLI's `die`, `warn` and `info` call the matching functions.

Out of scope: `aictl_parse`, the `aictl config` subcommand, and the
`timvisher_logging_data` map (bash-only).

## Reading the examples

Each example is a `### Example N:` section of fenced blocks:

- `env`: variables set for the call, one `NAME=value` per line; the
  value is everything after the first `=`, taken literally. Every
  example starts with none of
  `TIMVISHER_AGENT`, `CLAUDECODE`, `TIMVISHER_CODEX`,
  `timvisher_logging_log_level`, `TIMVISHER_AGENT_NIRMI`,
  `TIMVISHER_AGENT_NIRMI_REASON` or `TIMVISHER_AICTL_LOG` set, and with
  `XDG_STATE_HOME` pointing at an empty directory.
- `vars`: shell variables the call reads (bash assignments).
- `fixture`: the contents of a file whose path replaces `<FIXTURE>`.
- `stdin`: the call's standard input (empty when absent).
- `call`: one function or command with its arguments, in bash syntax.
  Placeholders are replaced first (their values contain no spaces or
  shell specials), then adapters split the line into words with bash.
- `stdout`, `stderr`, `status`: what the call must produce.
- `aictl-log`: the contents of the `TIMVISHER_AICTL_LOG` file after the
  call. `<AICTL_LOG>` in `env` names an existing empty file;
  `<AICTL_LOG_MISSING>` names a file that does not exist and must not
  be created.
- `audit-log`: the contents of the bypass audit log after the call;
  when absent, the audit log must not exist.

Before comparing, outputs are normalized: timestamps become `<TS>`, the
audit log's epoch seconds `<EPOCH>`, the call's working directory
`<CWD>`, and the fixture and aictl log paths `<FIXTURE>` and
`<AICTL_LOG>`.

## Examples

### Example 1: info with no level set and no agent logs everything, human format

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

### Example 2: warn in human format

```call
warn 'disk at %s%%' 90
```

```stdout
```

```stderr
<TS> WARN main: disk at 90%
```

```status
0
```

### Example 3: error in human format

```call
error 'cannot open %s' /tmp/missing
```

```stdout
```

```stderr
<TS> ERROR main: cannot open /tmp/missing
```

```status
0
```

### Example 4: trace in human format

```call
trace 'step %s of %s' 1 3
```

```stdout
```

```stderr
<TS> TRACE main: step 1 of 3
```

```status
0
```

### Example 5: an explicit level gates lower levels in human format

```env
timvisher_logging_log_level=ERROR
```

```call
warn 'not shown'
```

```stdout
```

```stderr
```

```status
0
```

### Example 6: an explicit level lets its own level through

```env
timvisher_logging_log_level=WARN
```

```call
warn 'shown'
```

```stdout
```

```stderr
<TS> WARN main: shown
```

```status
0
```

### Example 7: TRACE lets everything through

```env
timvisher_logging_log_level=TRACE
```

```call
trace 'deep'
```

```stdout
```

```stderr
<TS> TRACE main: deep
```

```status
0
```

### Example 8: an unknown level value logs everything

```env
timvisher_logging_log_level=BOGUS
```

```call
trace 'still shown'
```

```stdout
```

```stderr
<TS> TRACE main: still shown
```

```status
0
```

### Example 9: CLAUDECODE with no level defaults to ERROR: info is dropped

```env
CLAUDECODE=1
```

```call
info 'dropped'
```

```stdout
```

```stderr
```

```status
0
```

### Example 10: CLAUDECODE with no level defaults to ERROR: error stays human format

```env
CLAUDECODE=1
```

```call
error 'kept'
```

```stdout
```

```stderr
<TS> ERROR main: kept
```

```status
0
```

### Example 11: TIMVISHER_CODEX with no level defaults to ERROR

```env
TIMVISHER_CODEX=1
```

```call
info 'dropped'
```

```stdout
```

```stderr
```

```status
0
```

### Example 12: agent mode with no level defaults to ERROR: info is dropped

```env
TIMVISHER_AGENT=1
```

```call
info 'dropped'
```

```stdout
```

```stderr
```

```status
0
```

### Example 13: agent mode emits JSON log lines

```env
TIMVISHER_AGENT=1
```

```call
error 'cannot open %s' /tmp/missing
```

```stdout
```

```stderr
{"type":"log","level":"ERROR","caller":"main","message":"cannot open /tmp/missing"}
```

```status
0
```

### Example 14: agent mode with level INFO emits info

```env
TIMVISHER_AGENT=1
timvisher_logging_log_level=INFO
```

```call
info 'hello %s' world
```

```stdout
```

```stderr
{"type":"log","level":"INFO","caller":"main","message":"hello world"}
```

```status
0
```

### Example 15: agent mode with level INFO drops trace

```env
TIMVISHER_AGENT=1
timvisher_logging_log_level=INFO
```

```call
trace 'dropped'
```

```stdout
```

```stderr
```

```status
0
```

### Example 16: agent mode with level TRACE emits trace

```env
TIMVISHER_AGENT=1
timvisher_logging_log_level=TRACE
```

```call
trace 'step %s' 2
```

```stdout
```

```stderr
{"type":"log","level":"TRACE","caller":"main","message":"step 2"}
```

```status
0
```

### Example 17: agent mode with level WARN emits warn

```env
TIMVISHER_AGENT=1
timvisher_logging_log_level=WARN
```

```call
warn 'careful'
```

```stdout
```

```stderr
{"type":"log","level":"WARN","caller":"main","message":"careful"}
```

```status
0
```

### Example 18: agent mode escapes JSON specials in the message

```env
TIMVISHER_AGENT=1
```

```call
error $'quote " backslash \\ tab\t end'
```

```stdout
```

```stderr
{"type":"log","level":"ERROR","caller":"main","message":"quote \" backslash \\ tab\t end"}
```

```status
0
```

### Example 19: die logs at DIE and exits 1 in human format

```call
die 'fatal: %s' boom
```

```stdout
```

```stderr
<TS> DIE main: fatal: boom
```

```status
1
```

### Example 20: die emits a DIE JSON line and exits 1 in agent mode

```env
TIMVISHER_AGENT=1
```

```call
die 'fatal: %s' boom
```

```stdout
```

```stderr
{"type":"log","level":"DIE","caller":"main","message":"fatal: boom"}
```

```status
1
```

### Example 21: die is gated like ERROR

```env
timvisher_logging_log_level=ERROR
```

```call
die 'fatal'
```

```stdout
```

```stderr
<TS> DIE main: fatal
```

```status
1
```

### Example 22: info_v logs a variable's name and value

```vars
answer=42
```

```call
info_v answer
```

```stdout
```

```stderr
<TS> INFO info_v: answer: ‘42’
```

```status
0
```

### Example 23: error_v logs a variable's name and value

```vars
answer=42
```

```call
error_v answer
```

```stdout
```

```stderr
<TS> ERROR error_v: answer: ‘42’
```

```status
0
```

### Example 24: trace_v logs a variable's name and value

```vars
answer=42
```

```call
trace_v answer
```

```stdout
```

```stderr
<TS> TRACE trace_v: answer: ‘42’
```

```status
0
```

### Example 25: info_v in agent mode

```env
TIMVISHER_AGENT=1
timvisher_logging_log_level=INFO
```

```vars
answer=42
```

```call
info_v answer
```

```stdout
```

```stderr
{"type":"log","level":"INFO","caller":"info_v","message":"answer: ‘42’"}
```

```status
0
```

### Example 26: f_assert_v passes silently for a set variable

```vars
answer=42
```

```call
f_assert_v answer
```

```stdout
```

```stderr
```

```status
0
```

### Example 27: f_assert_v fails for an empty variable

```vars
answer=
```

```call
f_assert_v answer
```

```stdout
```

```stderr
<TS> ERROR f_assert_v: Variable ‘answer’ is empty
```

```status
1
```

### Example 28: info_array with a %s format logs each item through it

```call
info_array 'item: %s' a 'b c'
```

```stdout
```

```stderr
<TS> INFO info_array: item: a
<TS> INFO info_array: item: b c
```

```status
0
```

### Example 29: info_array without a format logs each argument as a message

```call
info_array first second
```

```stdout
```

```stderr
<TS> INFO info_array: first
<TS> INFO info_array: second
```

```status
0
```

### Example 30: trace_array with a %s format

```call
trace_array 'item: %s' a b
```

```stdout
```

```stderr
<TS> TRACE trace_array: item: a
<TS> TRACE trace_array: item: b
```

```status
0
```

### Example 31: error_array with a %s format

```call
error_array 'bad: %s' a b
```

```stdout
```

```stderr
<TS> ERROR error_array: bad: a
<TS> ERROR error_array: bad: b
```

```status
0
```

### Example 32: error_array without a format

```call
error_array first second
```

```stdout
```

```stderr
<TS> ERROR error_array: first
<TS> ERROR error_array: second
```

```status
0
```

### Example 33: info_array_v logs each element, dropping a trailing s from the name

```vars
items=(a 'b c')
```

```call
info_array_v items
```

```stdout
```

```stderr
<TS> INFO info_array: item: ‘a’
<TS> INFO info_array: item: ‘b c’
```

```status
0
```

### Example 34: trace_array_v

```vars
items=(a b)
```

```call
trace_array_v items
```

```stdout
```

```stderr
<TS> TRACE trace_array: item: ‘a’
<TS> TRACE trace_array: item: ‘b’
```

```status
0
```

### Example 35: error_array_v

```vars
items=(a b)
```

```call
error_array_v items
```

```stdout
```

```stderr
<TS> ERROR error_array: item: ‘a’
<TS> ERROR error_array: item: ‘b’
```

```status
0
```

### Example 36: info_stdout logs each stdin line numbered and passes stdin through

```stdin
alpha
beta
```

```call
info_stdout
```

```stdout
alpha
beta
```

```stderr
<TS> TRACE trace_v: log_copy: ‘alpha\nbeta\n’
<TS> INFO info_stdout: info stdout: ‘000001	alpha’
<TS> INFO info_stdout: info stdout: ‘000002	beta’
```

```status
0
```

### Example 37: info_stdout with a %s format

```stdin
alpha
```

```call
info_stdout 'out: %s'
```

```stdout
alpha
```

```stderr
<TS> TRACE trace_v: log_copy: ‘alpha\n’
<TS> INFO info_stdout: out: 000001	alpha
```

```status
0
```

### Example 38: error_stdout logs each stdin line numbered and passes stdin through

```stdin
alpha
beta
```

```call
error_stdout
```

```stdout
alpha
beta
```

```stderr
<TS> TRACE trace_v: log_copy: ‘alpha\nbeta\n’
<TS> ERROR error_stdout: error stdout: ‘000001	alpha’
<TS> ERROR error_stdout: error stdout: ‘000002	beta’
```

```status
0
```

### Example 39: info_stdout in agent mode at INFO

```env
TIMVISHER_AGENT=1
timvisher_logging_log_level=INFO
```

```stdin
alpha
```

```call
info_stdout
```

```stdout
alpha
```

```stderr
{"type":"log","level":"INFO","caller":"info_stdout","message":"info stdout: ‘000001\talpha’"}
```

```status
0
```

### Example 40: display_script logs a file's numbered lines

```fixture
echo one
echo two
```

```call
display_script <FIXTURE>
```

```stdout
```

```stderr
<TS> INFO display_script: Contents of <FIXTURE>
<TS> INFO display_script: 000001	echo one
<TS> INFO display_script: 000002	echo two
```

```status
0
```

### Example 41: aictl_info with positional arguments

```env
TIMVISHER_AGENT=1
```

```call
aictl_info my_code 'Something happened' 'Try this'
```

```stdout
```

```stderr
{"type":"instruction","level":"info","code":"my_code","message":"Something happened","suggestions":["Try this"]}
```

```status
0
```

### Example 42: aictl_info with every flag

```env
TIMVISHER_AGENT=1
```

```call
aictl_info --code my_code --message 'Done' --reason 'Because' --doc docs/x.md --suggestion 'First' --suggestion 'Second' --data '{"count":2}'
```

```stdout
```

```stderr
{"type":"instruction","level":"info","code":"my_code","message":"Done","reason":"Because","data":{"count":2},"suggestions":["First","Second"],"doc":"docs/x.md"}
```

```status
0
```

### Example 43: aictl_info with --data that is not JSON keeps it as a string

```env
TIMVISHER_AGENT=1
```

```call
aictl_info --code my_code --message 'Done' --data 'plain text'
```

```stdout
```

```stderr
{"type":"instruction","level":"info","code":"my_code","message":"Done","data":"plain text"}
```

```status
0
```

### Example 44: aictl_info with suggestions after --

```env
TIMVISHER_AGENT=1
```

```call
aictl_info --code c --message m -- 'one' 'two'
```

```stdout
```

```stderr
{"type":"instruction","level":"info","code":"c","message":"m","suggestions":["one","two"]}
```

```status
0
```

### Example 45: aictl_info escapes JSON specials

```env
TIMVISHER_AGENT=1
```

```call
aictl_info --code c --message $'say "hi"\nbye'
```

```stdout
```

```stderr
{"type":"instruction","level":"info","code":"c","message":"say \"hi\"\nbye"}
```

```status
0
```

### Example 46: aictl_info writes text on stderr without TIMVISHER_AGENT

```call
aictl_info c m
```

```stdout
```

```stderr
<TS> INFO c: m
```

```status
0
```

### Example 47: aictl_error emits a non-retryable error and returns 1

```env
TIMVISHER_AGENT=1
```

```call
aictl_error --code bad --message 'It broke'
```

```stdout
```

```stderr
{"type":"instruction","level":"error","code":"bad","message":"It broke","retryable":false}
```

```status
1
```

### Example 48: aictl_die emits a non-retryable error and exits 1

```env
TIMVISHER_AGENT=1
```

```call
aictl_die --code bad --message 'It broke' --suggestion 'Fix it'
```

```stdout
```

```stderr
{"type":"instruction","level":"error","code":"bad","message":"It broke","retryable":false,"suggestions":["Fix it"]}
```

```status
1
```

### Example 49: aictl_notice emits a warning without retryable and returns 0

```env
TIMVISHER_AGENT=1
```

```call
aictl_notice --code heads_up --message 'Long op'
```

```stdout
```

```stderr
{"type":"instruction","level":"warning","code":"heads_up","message":"Long op"}
```

```status
0
```

### Example 50: aictl_warn without a bypass emits a retryable warning and exits 1

```env
TIMVISHER_AGENT=1
```

```call
aictl_warn --code guarded --message 'Refusing' --command 'rm -rf x' --doc docs/guard.md
```

```stdout
```

```stderr
{"type":"instruction","level":"warning","code":"guarded","message":"Refusing","retryable":true,"doc":"docs/guard.md"}
```

```status
1
```

### Example 51: aictl_warn with NIRMI but no reason refuses with aictl_bypass_missing_reason

```env
TIMVISHER_AGENT=1
TIMVISHER_AGENT_NIRMI=1
```

```call
aictl_warn --code guarded --message 'Refusing'
```

```stdout
```

```stderr
{"type":"instruction","level":"error","code":"aictl_bypass_missing_reason","message":"TIMVISHER_AGENT_NIRMI=1 was set but TIMVISHER_AGENT_NIRMI_REASON is empty. Bypassing a guardrail now requires an explicit reason, which is logged for audit.","reason":"NIRMI-only bypasses were being used reflexively. Requiring a reason surfaces intent and creates an audit trail.","retryable":false,"suggestions":["Set TIMVISHER_AGENT_NIRMI_REASON='<why this specific bypass is necessary>' and retry","Or reconsider — the guard exists for a reason; try the suggested alternative instead"]}
```

```status
1
```

### Example 52: aictl_warn with NIRMI and a reason bypasses, logs the audit line and returns 0

```env
TIMVISHER_AGENT=1
TIMVISHER_AGENT_NIRMI=1
TIMVISHER_AGENT_NIRMI_REASON=needed for the demo
```

```call
aictl_warn --code guarded --message 'Refusing'
```

```stdout
```

```stderr
{"type":"instruction","level":"bypass","code":"guarded","message":"Guardrail bypassed with logged reason. Be sure you know what you are doing."}
```

```status
0
```

```audit-log
{"ts":<EPOCH>,"code":"guarded","reason":"needed for the demo","cwd":"<CWD>"}
```

### Example 53: aictl_warn's audit line records the --command

```env
TIMVISHER_AGENT=1
TIMVISHER_AGENT_NIRMI=1
TIMVISHER_AGENT_NIRMI_REASON=needed
```

```call
aictl_warn --code guarded --message 'Refusing' --command 'rm -rf x'
```

```stdout
```

```stderr
{"type":"instruction","level":"bypass","code":"guarded","message":"Guardrail bypassed with logged reason. Be sure you know what you are doing."}
```

```status
0
```

```audit-log
{"ts":<EPOCH>,"code":"guarded","reason":"needed","cwd":"<CWD>","command":"rm -rf x"}
```

### Example 54: a reason without NIRMI does not bypass

```env
TIMVISHER_AGENT=1
TIMVISHER_AGENT_NIRMI_REASON=needed
```

```call
aictl_warn --code guarded --message 'Refusing'
```

```stdout
```

```stderr
{"type":"instruction","level":"warning","code":"guarded","message":"Refusing","retryable":true}
```

```status
1
```

### Example 55: TIMVISHER_AICTL_LOG receives the JSON while stderr is text

```env
TIMVISHER_AICTL_LOG=<AICTL_LOG>
```

```call
aictl_info c 'routed'
```

```stdout
```

```stderr
<TS> INFO c: routed
```

```status
0
```

```aictl-log
{"type":"instruction","level":"info","code":"c","message":"routed"}
```

### Example 56: TIMVISHER_AICTL_LOG receives a bypass line too

```env
TIMVISHER_AICTL_LOG=<AICTL_LOG>
TIMVISHER_AGENT_NIRMI=1
TIMVISHER_AGENT_NIRMI_REASON=needed
```

```call
aictl_warn --code guarded --message 'Refusing'
```

```stdout
```

```stderr
<TS> BYPASS guarded: Guardrail bypassed with logged reason. Be sure you know what you are doing.
```

```status
0
```

```aictl-log
{"type":"instruction","level":"bypass","code":"guarded","message":"Guardrail bypassed with logged reason. Be sure you know what you are doing."}
```

```audit-log
{"ts":<EPOCH>,"code":"guarded","reason":"needed","cwd":"<CWD>"}
```

### Example 57: TIMVISHER_AICTL_LOG naming a missing file is not created

```env
TIMVISHER_AICTL_LOG=<AICTL_LOG_MISSING>
```

```call
aictl_info c 'not routed'
```

```stdout
```

```stderr
<TS> INFO c: not routed
```

```status
0
```

### Example 58: aictl_listening is true under TIMVISHER_AGENT

```env
TIMVISHER_AGENT=1
```

```call
aictl_listening
```

```stdout
```

```stderr
```

```status
0
```

### Example 59: aictl_listening is true when TIMVISHER_AICTL_LOG is set

```env
TIMVISHER_AICTL_LOG=<AICTL_LOG>
```

```call
aictl_listening
```

```stdout
```

```stderr
```

```status
0
```

```aictl-log
```

### Example 60: aictl_listening is false otherwise

```call
aictl_listening
```

```stdout
```

```stderr
```

```status
1
```

### Example 61: the aictl CLI's info

```env
TIMVISHER_AGENT=1
```

```call
aictl info my_code 'Something happened' 'Try this'
```

```stdout
```

```stderr
{"type":"instruction","level":"info","code":"my_code","message":"Something happened","suggestions":["Try this"]}
```

```status
0
```

### Example 62: the aictl CLI's die exits 1

```env
TIMVISHER_AGENT=1
```

```call
aictl die my_code 'It broke'
```

```stdout
```

```stderr
{"type":"instruction","level":"error","code":"my_code","message":"It broke","retryable":false}
```

```status
1
```

### Example 63: the aictl CLI's warn exits 1 without a bypass

```env
TIMVISHER_AGENT=1
```

```call
aictl warn my_code 'Refusing'
```

```stdout
```

```stderr
{"type":"instruction","level":"warning","code":"my_code","message":"Refusing","retryable":true}
```

```status
1
```

### Example 64: the aictl CLI's warn bypasses with NIRMI and a reason

```env
TIMVISHER_AGENT=1
TIMVISHER_AGENT_NIRMI=1
TIMVISHER_AGENT_NIRMI_REASON=needed
```

```call
aictl warn my_code 'Refusing'
```

```stdout
```

```stderr
{"type":"instruction","level":"bypass","code":"my_code","message":"Guardrail bypassed with logged reason. Be sure you know what you are doing."}
```

```status
0
```

```audit-log
{"ts":<EPOCH>,"code":"my_code","reason":"needed","cwd":"<CWD>"}
```

### Example 65: the text form carries reason, suggestions and doc, not data

```call
aictl_info --code my_code --message 'Done' --reason 'Because' --doc docs/x.md --suggestion 'First' --suggestion 'Second' --data '{"count":2}'
```

```stdout
```

```stderr
<TS> INFO my_code: Done
  reason: Because
  suggestion: First
  suggestion: Second
  doc: docs/x.md
```

```status
0
```

### Example 66: the text form of an empty message is the code alone

```call
aictl_info --code c --message ''
```

```stdout
```

```stderr
<TS> INFO c
```

```status
0
```

### Example 67: aictl_die in text form

```call
aictl_die --code bad --message 'It broke' --suggestion 'Fix it'
```

```stdout
```

```stderr
<TS> ERROR bad: It broke
  suggestion: Fix it
```

```status
1
```
