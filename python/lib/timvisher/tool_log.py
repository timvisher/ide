"""Append one line per call to the shared tool log.

The Python twin of bash/functions/tool_log.bash: same directory, same
line format, same caller rules, so timvisher_tool_log reads both
(cf-m1w0.28).  Only argv is logged, never the environment.
"""

from __future__ import annotations

import datetime
import json
import os
import re
import socket
import sys
from pathlib import Path

_SECRET_FLAGS = {
    "--token", "--password", "--passwd", "--secret", "--api-key", "--apikey",
    "--client-secret", "--auth", "--auth-token", "--access-token",
    "--with-token", "--private-key",
}
_SECRET_NAME = re.compile(
    r"token|password|passwd|secret|api_key|apikey|api-key|private_key|credential",
    re.IGNORECASE,
)
_SECRET_SHAPE = re.compile(
    r"^(ghp_|gho_|ghu_|ghs_|ghr_|github_pat_|sk-|xoxb-|xoxp-|glpat-)"
    r"|^eyJ[^.]*\.[^.]*\.|[Aa]uthorization:|^[Bb]earer |AKIA[0-9A-Z]{16}"
)


def log_dir() -> Path:
    override = os.environ.get("TIMVISHER_TOOL_LOG_DIR")
    if override:
        return Path(override)
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Logs" / "timvisher" / "tools"
    state = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(state) / "timvisher" / "logs"


def redact(argv: list[str]) -> list[str]:
    out: list[str] = []
    redact_next = False
    for arg in argv:
        if redact_next:
            out.append("<redacted>")
            redact_next = False
            continue
        if _SECRET_SHAPE.search(arg):
            out.append("<redacted>")
        elif arg.lower() in _SECRET_FLAGS:
            out.append(arg)
            redact_next = True
        elif "=" in arg and (
            _SECRET_NAME.search(arg.split("=", 1)[0])
            or arg.split("=", 1)[0].lower() in _SECRET_FLAGS
        ):
            out.append(arg.split("=", 1)[0] + "=<redacted>")
        else:
            out.append(arg)
    return out


def caller() -> dict:
    sessions = Path(
        os.environ.get("TIMVISHER_TOOL_LOG_SESSIONS_DIR")
        or Path.home() / ".claude" / "sessions"
    )
    pid = os.environ.get("CLAUDE_PID", "")
    if pid.isdigit():
        try:
            os.kill(int(pid), 0)
            data = json.loads((sessions / f"{pid}.json").read_text())
        except (OSError, ValueError):
            data = None
        if isinstance(data, dict):
            return {
                "kind": "claude",
                "pid": int(pid),
                "session_id": data.get("sessionId", ""),
                "name": data.get("name", ""),
            }
    if os.environ.get("CLAUDE_CODE_SESSION_ID"):
        return {"kind": "claude", "session_id": os.environ["CLAUDE_CODE_SESSION_ID"]}
    if os.environ.get("TIMVISHER_TOOL_LOG_CALLER_SESSION"):
        return {
            "kind": "claude",
            "session_id": os.environ["TIMVISHER_TOOL_LOG_CALLER_SESSION"],
            "name": os.environ.get("TIMVISHER_TOOL_LOG_CALLER_NAME", ""),
            "forwarded": True,
        }
    if os.environ.get("TIMVISHER_CODEX"):
        exec_pid = os.environ.get("TIMVISHER_AGENT_WRAPPER_EXEC", "").split(":", 1)[0]
        return {"kind": "codex", "pid": int(exec_pid) if exec_pid.isdigit() else None}
    try:
        tty = os.ttyname(0).removeprefix("/dev/")
    except OSError:
        tty = "none"
    return {"kind": "human", "tty": tty}


def write(tool: str, real: str, argv: list[str], rc: int, t0: float, **extra) -> None:
    """Append the line for one finished call; never raises."""
    now = datetime.datetime.now(datetime.timezone.utc).timestamp()
    record = {
        "ts": datetime.datetime.fromtimestamp(t0, datetime.timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z"),
        "epoch": t0,
        "tool": tool,
        "real": real,
        "argv": redact(argv),
        "cwd": os.getcwd(),
        "rc": rc,
        "duration_ms": int((now - t0) * 1000),
        "host": socket.gethostname().split(".", 1)[0],
        "caller": caller(),
        **extra,
    }
    directory = log_dir()
    try:
        directory.mkdir(parents=True, exist_ok=True)
        with open(directory / f"{tool}.jsonl", "a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, separators=(",", ":")) + "\n")
    except OSError:
        print(f"tool_log: could not append to {directory / (tool + '.jsonl')}", file=sys.stderr)
