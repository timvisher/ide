import json
import os
import pathlib
import sys
import time

_FLAGS = {
    "--code": "code",
    "--message": "message",
    "--reason": "reason",
    "--doc": "doc",
    "--command": "command",
    "--data": "data",
}


def _parse(args, fields):
    args = list(args)
    suggestions = list(fields.pop("suggestions", None) or ())
    while args:
        arg = args.pop(0)
        if arg in _FLAGS:
            fields[_FLAGS[arg]] = args.pop(0) if args else ""
        elif arg == "--suggestion":
            suggestions.append(args.pop(0) if args else "")
        elif arg == "--":
            suggestions.extend(args)
            break
        elif not fields.get("code"):
            fields["code"] = arg
        elif not fields.get("message"):
            fields["message"] = arg
        else:
            suggestions.append(arg)
    fields["suggestions"] = suggestions
    return fields


def _data(value):
    if not isinstance(value, str):
        return value
    try:
        return json.loads(value)
    except ValueError:
        return value


_LABELS = {"error": "ERROR", "warning": "WARN", "info": "INFO", "bypass": "BYPASS"}


def _indent(text):
    return text.replace("\n", "\n    ")


def _human(record):
    level = record["level"]
    label = _LABELS.get(level, level.upper())
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S+0000", time.gmtime())
    head = record.get("code") or ""
    if record.get("message"):
        head += (": " if head else "") + _indent(record["message"])
    lines = [f"{stamp} {label}" + (f" {head}" if head else "")]
    if record.get("reason"):
        lines.append(f"  reason: {_indent(record['reason'])}")
    for suggestion in record.get("suggestions") or ():
        lines.append(f"  suggestion: {_indent(suggestion)}")
    if record.get("doc"):
        lines.append(f"  doc: {_indent(record['doc'])}")
    return "\n".join(lines)


def _write(record):
    line = json.dumps(record, ensure_ascii=False, separators=(",", ":"))
    log = os.environ.get("TIMVISHER_AICTL_LOG")
    if log and os.path.isfile(log):
        try:
            with open(log, "a", encoding="utf-8") as stream:
                stream.write(line + "\n")
        except OSError:
            pass
    if os.environ.get("TIMVISHER_AGENT"):
        sys.stderr.write(line + "\n")
    else:
        sys.stderr.write(_human(record) + "\n")
    sys.stderr.flush()


def _emit(level, args, fields, retryable=True):
    fields = _parse(args, fields)
    record = {
        "type": "instruction",
        "level": level,
        "code": fields.get("code") or "",
        "message": fields.get("message") or "",
    }
    if fields.get("reason"):
        record["reason"] = fields["reason"]
    if level == "error":
        record["retryable"] = False
    elif level == "warning" and retryable:
        record["retryable"] = True
    if fields.get("data") not in (None, ""):
        record["data"] = _data(fields["data"])
    if fields["suggestions"]:
        record["suggestions"] = fields["suggestions"]
    if fields.get("doc"):
        record["doc"] = fields["doc"]
    _write(record)
    return fields


def die(*args, **fields):
    _emit("error", args, fields)
    raise SystemExit(1)


def error(*args, **fields):
    _emit("error", args, fields)
    return False


def info(*args, **fields):
    _emit("info", args, fields)


def notice(*args, **fields):
    _emit("warning", args, fields, retryable=False)


def _cwd():
    logical = os.environ.get("PWD")
    try:
        if logical and os.path.samefile(logical, "."):
            return logical
        return os.getcwd()
    except OSError:
        return logical or ""


def _audit(fields):
    state = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    directory = pathlib.Path(state) / "timvisher" / "wrappers" / "aictl-bypass"
    entry = {
        "ts": int(time.time()),
        "code": fields.get("code") or "",
        "reason": os.environ["TIMVISHER_AGENT_NIRMI_REASON"],
        "cwd": _cwd(),
    }
    if fields.get("command"):
        entry["command"] = fields["command"]
    try:
        directory.mkdir(parents=True, exist_ok=True)
        with open(directory / "log.jsonl", "a", encoding="utf-8") as stream:
            stream.write(json.dumps(entry, ensure_ascii=False, separators=(",", ":")) + "\n")
    except OSError:
        pass


def warn(*args, **fields):
    if os.environ.get("TIMVISHER_AGENT_NIRMI"):
        if not os.environ.get("TIMVISHER_AGENT_NIRMI_REASON"):
            _emit(
                "error",
                (),
                {
                    "code": "aictl_bypass_missing_reason",
                    "message": "TIMVISHER_AGENT_NIRMI=1 was set but TIMVISHER_AGENT_NIRMI_REASON is empty. Bypassing a guardrail now requires an explicit reason, which is logged for audit.",
                    "reason": "NIRMI-only bypasses were being used reflexively. Requiring a reason surfaces intent and creates an audit trail.",
                    "suggestions": [
                        "Set TIMVISHER_AGENT_NIRMI_REASON='<why this specific bypass is necessary>' and retry",
                        "Or reconsider — the guard exists for a reason; try the suggested alternative instead",
                    ],
                },
            )
            raise SystemExit(1)
        parsed = _parse(args, dict(fields))
        _audit(parsed)
        _write(
            {
                "type": "instruction",
                "level": "bypass",
                "code": parsed.get("code") or "",
                "message": "Guardrail bypassed with logged reason. Be sure you know what you are doing.",
            }
        )
        return None
    _emit("warning", args, fields)
    raise SystemExit(1)


def listening():
    return bool(os.environ.get("TIMVISHER_AGENT") or os.environ.get("TIMVISHER_AICTL_LOG"))
