import datetime
import json
import os
import re
import sys

LEVELS = {"ERROR": 0, "WARN": 1, "INFO": 2, "TRACE": 3, "DIE": 0}
_SPEC = re.compile(r"%(%|[-+ #0]*\d*(?:\.\d+)?[sdif])")
_ESCAPES = {"\\": "\\", "n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "a": "\a", "v": "\v"}


def _escapes(text):
    out = []
    i = 0
    while i < len(text):
        char = text[i]
        if char == "\\" and i + 1 < len(text) and text[i + 1] in _ESCAPES:
            out.append(_ESCAPES[text[i + 1]])
            i += 2
        else:
            out.append(char)
            i += 1
    return "".join(out)


def printf(fmt, *args):
    fmt = _escapes(fmt)
    args = list(args)
    out = []
    while True:
        used = 0

        def convert(match):
            nonlocal used
            spec = match.group(1)
            if spec == "%":
                return "%"
            value = args[used] if used < len(args) else None
            used += 1
            kind = spec[-1]
            if kind == "s":
                return ("%" + spec) % ("" if value is None else str(value))
            number = 0 if value in (None, "") else value
            if kind in "di":
                return ("%" + spec) % int(number)
            return ("%" + spec) % float(number)

        out.append(_SPEC.sub(convert, fmt))
        if used == 0 or len(args) <= used:
            break
        args = args[used:]
    return "".join(out)


def _caller(depth):
    frame = sys._getframe(depth)
    name = frame.f_code.co_name
    return "main" if name == "<module>" else name


def _should_log(level):
    configured = os.environ.get("timvisher_logging_log_level", "")
    if not configured:
        if any(os.environ.get(name) for name in ("CLAUDECODE", "TIMVISHER_CODEX", "TIMVISHER_AGENT")):
            configured = "ERROR"
        else:
            return True
    if configured not in LEVELS:
        return True
    return LEVELS.get(level, LEVELS["ERROR"]) <= LEVELS[configured]


def _log(level, fmt, args, depth=3):
    if not _should_log(level):
        return
    message = printf(fmt, *args)
    caller = _caller(depth)
    if os.environ.get("TIMVISHER_AGENT"):
        line = json.dumps(
            {"type": "log", "level": level, "caller": caller, "message": message},
            ensure_ascii=False,
            separators=(",", ":"),
        )
    else:
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+0000")
        line = f"{stamp} {level} {caller}: {message}"
    sys.stderr.write(line + "\n")
    sys.stderr.flush()


def die(fmt="", *args):
    _log("DIE", fmt, args)
    raise SystemExit(1)


def info(fmt="", *args):
    _log("INFO", fmt, args)


def warn(fmt="", *args):
    _log("WARN", fmt, args)


def trace(fmt="", *args):
    _log("TRACE", fmt, args)


def error(fmt="", *args):
    _log("ERROR", fmt, args)


# Python has no dynamic scope: a variable is looked up in the calling
# function's locals, then its module's globals, not further up the stack
# as bash's ${!name} would.
def _variable(name, depth=2):
    frame = sys._getframe(depth)
    if name in frame.f_locals:
        return frame.f_locals[name]
    return frame.f_globals.get(name)


def _empty(value):
    return value is None or value == "" or value == [] or value == ()


def _scalar(value):
    if isinstance(value, (list, tuple)):
        return value[0] if value else ""
    return "" if value is None else value


def info_v(name):
    info("%s: ‘%s’", name, _scalar(_variable(name)))


def error_v(name):
    error("%s: ‘%s’", name, _scalar(_variable(name)))


def trace_v(name):
    trace("%s: ‘%s’", name, _scalar(_variable(name)))


def f_assert_v(name):
    if _empty(_scalar(_variable(name))):
        error("Variable ‘%s’ is empty", name)
        return False
    return True


def info_array(*args):
    if args and "%s" in args[0]:
        for item in args[1:]:
            info(args[0], item)
    else:
        for item in args:
            info(item)


def trace_array(*args):
    if args and "%s" in args[0]:
        for item in args[1:]:
            trace(args[0], item)
    else:
        for item in args:
            trace(item)


def error_array(*args):
    if args and "%s" in args[0]:
        for item in args[1:]:
            error(args[0], item)
    else:
        for item in args:
            error(item)


def _elements(name):
    value = _variable(name, depth=3)
    if isinstance(value, (list, tuple)):
        return list(value)
    return [] if value is None else [value]


def _label(name):
    return name[:-1] if name.endswith("s") else name


def info_array_v(name):
    info_array(f"{_label(name)}: ‘%s’", *_elements(name))


def trace_array_v(name):
    trace_array(f"{_label(name)}: ‘%s’", *_elements(name))


def error_array_v(name):
    error_array(f"{_label(name)}: ‘%s’", *_elements(name))


def _numbered(lines):
    out = []
    number = 0
    for line in lines:
        if line:
            number += 1
            out.append(f"{number:06d}\t{line}")
        else:
            out.append(line)
    return out


def _read_lines(stream):
    return stream.read().split("\n")[:-1]


def info_stdout(fmt=None, stream=None):
    msg = fmt if fmt is not None and "%s" in fmt else "info stdout: ‘%s’"
    log_copy = "".join(line + "\\n" for line in _read_lines(stream or sys.stdin))
    trace_v("log_copy")
    for line in _numbered(printf(log_copy).split("\n")[:-1]):
        info(msg, line)
    sys.stdout.write(printf(log_copy))
    sys.stdout.flush()


def error_stdout(fmt=None, stream=None):
    msg = fmt if fmt is not None and "%s" in fmt else "error stdout: ‘%s’"
    log_copy = "".join(line + "\\n" for line in _read_lines(stream or sys.stdin))
    trace_v("log_copy")
    for line in _numbered(printf(log_copy).split("\n")[:-1]):
        error(msg, line)
    sys.stdout.write(printf(log_copy))
    sys.stdout.flush()


def display_script(path):
    info("Contents of " + path)
    with open(path, encoding="utf-8") as script:
        lines = script.read().split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    for line in _numbered(lines):
        info("%s", line.strip())
