import json
import os
import re
import subprocess
import sys
import tempfile
import time

from timvisher import aictl, logging
from timvisher.gh import fetch, hooks, nouns, pr, record, state, store, targets
from timvisher.gh.errors import ERROR, fail, usage

USAGE = """\
Usage: timvisher_gh [-C <path>] pr ready [<target>]

Wait for the PR's checks to pass, then mark it ready for review. Checks
matching a pattern in <root>/{orgs/O,repos/O/R}/pr/ready/exclude-checks.txt
(either config root; one regex per line, '#' comments and blank lines
skipped) are ignored. A PR that's already ready skips the checks and the
pre-hooks. TIMVISHER_GH_PR_READY_POLL_INTERVAL sets the poll interval in
seconds (default 10).
"""


def exclude_patterns(spec):
    owner = spec.split("/")[0]
    patterns = []
    for root in hooks.roots():
        for path in (root / "orgs" / owner / "pr" / "ready" / "exclude-checks.txt",
                     root / "repos" / spec / "pr" / "ready" / "exclude-checks.txt"):
            if not path.is_file():
                continue
            for line in path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    try:
                        patterns.append(re.compile(line))
                    except re.error as error:
                        fail("timvisher_gh_bad_exclude_pattern",
                             f"'{line}' in {path} isn't a valid regex, so checks can't be filtered.",
                             reason=str(error), suggestions=[f"Fix or remove it in {path}, then rerun"])
            logging.info("Loaded exclude pattern(s) from %s", path)
    return patterns


def _refused(lines):
    for line in lines:
        try:
            instruction = json.loads(line)
        except ValueError:
            continue
        if isinstance(instruction, dict) and instruction.get("type") == "instruction" and instruction.get("level") == "error":
            return True
    return False


# gh reports a refusal on stderr in JSON only under TIMVISHER_AGENT, so each
# call gets its own TIMVISHER_AICTL_LOG to read it from, as #6 does; what it
# records is passed on to the caller's log.
def _checks(spec, url):
    with tempfile.NamedTemporaryFile("r", prefix="timvisher_gh_pr_ready.", suffix=".jsonl") as log:
        done = subprocess.run(["gh", "-R", spec, "pr", "checks", url, "--json", "name,bucket"],
                              env={**os.environ, "TIMVISHER_AICTL_LOG": log.name},
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        instructions = log.read().splitlines()
    outer = os.environ.get("TIMVISHER_AICTL_LOG")
    if instructions and outer and os.path.isfile(outer):
        with open(outer, "a", encoding="utf-8") as stream:
            stream.write("".join(f"{line}\n" for line in instructions))
    return done, instructions


def wait_for_checks(spec, url, patterns, interval):
    while True:
        done, instructions = _checks(spec, url)
        if _refused(instructions):
            sys.stderr.write(done.stderr)
            fail("timvisher_gh_checks_refused", f"gh refused to check {url}; not retrying.",
                 suggestions=["Fix what gh reported above, then rerun"])
        try:
            checks = json.loads(done.stdout)
        except ValueError:
            checks = None
        if not isinstance(checks, list):
            aictl.notice(code="timvisher_gh_checks_retry", message=f"No checks found yet on {url}; retrying in {interval}s.",
                         reason=done.stderr.strip() or None)
            time.sleep(interval)
            continue
        kept = [c for c in checks if not any(p.search(c["name"]) for p in patterns)]
        failed = [c["name"] for c in kept if c["bucket"] == "fail"]
        pending = [c for c in kept if c["bucket"] == "pending"]
        logging.info("Checks: %d total, %d pass, %d pending, %d fail", len(kept),
                     sum(c["bucket"] == "pass" for c in kept), len(pending), len(failed))
        if failed:
            fail("timvisher_gh_checks_failed", f"CI checks failed on {url}; not marking it ready.",
                 reason=", ".join(failed), suggestions=["Fix the failing checks, then rerun 'timvisher_gh pr ready'"])
        if not pending:
            return
        logging.info("Waiting for %d pending check(s); retrying in %ds", len(pending), interval)
        time.sleep(interval)


def run(context, args):
    target = None
    for arg in args:
        if arg in ("-h", "--help"):
            sys.stdout.write(USAGE)
            return 0
        if arg.startswith("-") or target is not None:
            usage(f"pr ready: unexpected argument '{arg}'", "See 'timvisher_gh pr ready --help'")
        target = arg
    opened = state.open_state()
    try:
        store.exporting(opened, lambda object_id: record.record(opened.db, object_id), nouns.now)
        found = targets.resolve("pr", target, context=context, db=opened.db, creating=True)
        if found.kind == "source":
            fail("timvisher_gh_pr_missing", f"There's no PR for {found.source} to mark ready.",
                 suggestions=["Create it with 'timvisher_gh pr push'"])
        if found.kind not in nouns.ACCEPTS["pr"]:
            usage(f"'{found.url}' names a {found.kind}, so pr ready can't use it.")
        spec = f"{found.owner}/{found.repo}"
        now = nouns.now()
        with opened.write():
            pr_id = fetch.Fetcher(opened, now).pr(found.owner, found.repo, found.number, conversation=False)
        raw = json.loads(opened.db.execute("SELECT payload FROM raw WHERE object_id = ?", (pr_id,)).fetchone()[0])
        url = raw["html_url"]
        worktree = context.toplevel if context else None
        source_file = store.store_file(opened.db, pr_id)
        ready_hooks = hooks.Hooks(repo=spec, worktree=worktree, pr_url=url,
                                  title=lambda: pr.parse_source(source_file.read_text(encoding="utf-8"))["title"]
                                  if source_file.exists() else raw["title"], state_dir=source_file.parent)
        if raw["draft"]:
            wait_for_checks(spec, url, exclude_patterns(spec),
                            int(os.environ.get("TIMVISHER_GH_PR_READY_POLL_INTERVAL") or 10))
            if not ready_hooks.pre("ready"):
                return ERROR
            fetch.api(spec, "graphql", "-f", f"query={pr.MARK_READY}", "-f", f"id={pr_id}")
            with opened.write() as db:
                pr.set_source_state(db, pr_id, {"draft": False}, now)
                fetch.Fetcher(opened, now).pr(found.owner, found.repo, found.number, conversation=False)
            aictl.info(code="timvisher_gh_pr_ready", message=f"Marked {url} ready for review.")
        else:
            with opened.write() as db:
                pr.set_source_state(db, pr_id, {"draft": False}, now)
            aictl.info(code="timvisher_gh_pr_already_ready", message=f"{url} is already ready for review.")
        post_ok = ready_hooks.post("ready")
        print(url)
        return 0 if post_ok else ERROR
    except fetch.NotFound as missing:
        fail("timvisher_gh_not_found", f"GitHub has no such PR ({missing}).",
             suggestions=["Check the URL, and that your gh account can see the repository"])
    finally:
        opened.close()
