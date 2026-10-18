import json
import subprocess

SCHEMA_VERSION = 1


def _run(*args):
    return subprocess.run(
        ["timvisher_browser", *args], check=True, stdout=subprocess.PIPE, text=True
    ).stdout


def active_tab():
    return json.loads(_run("tab", "info", "--schema-version", str(SCHEMA_VERSION)))


def open_tab(url):
    return _run("tab", url).rstrip("\n")


def close_tab(url):
    _run("tab", "close", url)
