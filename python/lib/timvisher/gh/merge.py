import os
import pathlib
import subprocess
import sys
import time

from timvisher import aictl, browser, logging
from timvisher.gh import fetch, hooks, nouns, pr, record, state, store, targets
from timvisher.gh.errors import ERROR, Exit, fail, usage

USAGE = """\
Usage: timvisher_gh [-C <path>] pr merge [<target>] [--open] [-- <gh pr merge args>]

Merge the PR. Its state is read first: an already merged PR records that
and stops; a closed one is an error; a merge already requested (auto-merge,
the merge queue, or your '/merge' since the last push in a comment-merge
repo) is waited for. Otherwise the merge pre-hooks run and, after you
confirm, a repo listed in ~/.config/timvisher/ide/gh-pr-merge-comment-repos
gets a '/merge' comment, and any other is merged with 'gh pr merge', trying
merge, squash and rebase as the repo allows. It then waits until the PR is
merged (TIMVISHER_GH_PR_MERGE_POLL_INTERVAL, default 10 seconds;
TIMVISHER_GH_PR_MERGE_TIMEOUT, default 7200), records the merge and pulls
the trunk worktree in the background (log: <trunk>/.timvisher_gh/trunk-pull.log).
"""

MERGE_STATE = """query MergeState($owner: String!, $repo: String!, $number: Int!) {
  viewer { login }
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      state
      baseRefName
      isInMergeQueue
      autoMergeRequest { enabledAt }
      mergeCommit { oid }
      commits(last: 1) { nodes { commit { committedDate } } }
      timelineItems(last: 100, itemTypes: [HEAD_REF_FORCE_PUSHED_EVENT, ISSUE_COMMENT]) {
        nodes {
          __typename
          ... on HeadRefForcePushedEvent { createdAt }
          ... on IssueComment { createdAt body author { login } }
        }
      }
    }
  }
}"""

def comment_merge(spec):
    path = pathlib.Path(os.path.expanduser("~")) / ".config/timvisher/ide/gh-pr-merge-comment-repos"
    if not path.is_file():
        return False
    return spec.lower() in {line.strip().lower() for line in path.read_text(encoding="utf-8").splitlines()}


def merge_state(target):
    spec = f"{target.owner}/{target.repo}"
    found = fetch.api(spec, "graphql", "-f", f"query={MERGE_STATE}", "-f", f"owner={target.owner}",
                      "-f", f"repo={target.repo}", "-F", f"number={target.number}")
    return {**found["data"]["repository"]["pullRequest"], "viewer": found["data"]["viewer"]["login"]}


def requested(pull, by_comment):
    if pull.get("autoMergeRequest"):
        return "auto-merge is enabled"
    if pull.get("isInMergeQueue"):
        return "the PR is in the merge queue"
    if by_comment:
        nodes = pull["timelineItems"]["nodes"]
        pushes = [n["createdAt"] for n in nodes if n["__typename"] == "HeadRefForcePushedEvent"]
        pushes += [n["commit"]["committedDate"] for n in pull["commits"]["nodes"] if n.get("commit")]
        last_push = max(pushes, default=None)
        for node in nodes:
            if (node["__typename"] == "IssueComment" and node["author"]["login"].lower() == pull["viewer"].lower()
                    and node["body"].strip() == "/merge" and (last_push is None or last_push < node["createdAt"])):
                return "you already commented '/merge' since the last push"
    return None


def _confirm(question, default):
    sys.stderr.write(f"{question} {'Y/n' if default else 'y/N'} ")
    sys.stderr.flush()
    answer = sys.stdin.readline().strip().lower()
    if not sys.stdin.isatty():
        sys.stderr.write("\n")
    return answer.startswith("y") if answer else default


def request_by_comment(target):
    if not _confirm(f"Request merge for {target.pr_url} by commenting '/merge'?", False):
        aictl.info(code="timvisher_gh_merge_declined", message=f"Didn't request a merge of {target.pr_url}.")
        return None
    spec = f"{target.owner}/{target.repo}"
    fetch.api(spec, f"repos/{spec}/issues/{target.number}/comments", "-f", "body=/merge")
    return "comment"


def request_by_gh(target, extra):
    spec = f"{target.owner}/{target.repo}"
    settings = fetch.api(spec, f"repos/{spec}")
    strategies = [name for name, key in (("merge", "allow_merge_commit"), ("squash", "allow_squash_merge"),
                                         ("rebase", "allow_rebase_merge")) if settings.get(key)]
    if not strategies:
        fail("timvisher_gh_no_merge_strategy", f"{spec} allows no merge strategy: merge, squash and rebase are all off.",
             suggestions=[f"Enable one in {spec}'s settings, or merge it on GitHub"])
    if not _confirm(f"Really merge {target.pr_url}?", False):
        aictl.info(code="timvisher_gh_merge_declined", message=f"Didn't merge {target.pr_url}.")
        return None
    for index, strategy in enumerate(strategies):
        done = subprocess.run(["gh", "-R", spec, "pr", "merge", *extra, f"--{strategy}", target.pr_url])
        if done.returncode == 0:
            return strategy
        following = strategies[index + 1] if index + 1 < len(strategies) else None
        if following and not _confirm(f"Merge with '{strategy}' failed. Try '{following}'?", True):
            fail("timvisher_gh_merge_aborted", f"Aborted after '{strategy}' failed to merge {target.pr_url}.",
                 suggestions=["Merge it on GitHub, or rerun 'timvisher_gh pr merge'"])
    fail("timvisher_gh_merge_failed", f"Couldn't merge {target.pr_url} with any strategy (tried {', '.join(strategies)}).",
         suggestions=["See gh's errors above"])


def wait_until_merged(target):
    spec = f"{target.owner}/{target.repo}"
    interval = int(os.environ.get("TIMVISHER_GH_PR_MERGE_POLL_INTERVAL") or 10)
    timeout = int(os.environ.get("TIMVISHER_GH_PR_MERGE_TIMEOUT") or 7200)
    started = time.monotonic()
    while True:
        pull = fetch.api(spec, f"repos/{spec}/pulls/{target.number}")
        if pull.get("merged"):
            return pull.get("merge_commit_sha")
        if pull["state"] == "closed":
            fail("timvisher_gh_pr_closed", f"{target.pr_url} was closed without merging.",
                 suggestions=["Reopen it on GitHub to merge it"])
        waited = time.monotonic() - started
        if timeout <= waited:
            fail("timvisher_gh_merge_timeout",
                 f"Timed out after {int(waited)}s waiting for {target.pr_url} to merge; it may still land.",
                 suggestions=["Rerun 'timvisher_gh pr merge' to keep waiting"])
        logging.info("Waiting for the merge to complete (state=%s); retrying in %ds", pull["state"], interval)
        time.sleep(interval)


TRUNK_PULL = """printf '%s git pull --ff-only after %s\\n' "$(date -u '+%FT%TZ')" "$3" >> "$2"
if ! git -C "$1" pull --ff-only >> "$2" 2>&1
then
  timvisher_notify 'timvisher_gh: trunk pull failed' "git pull --ff-only failed in $1; see $2" >> "$2" 2>&1
fi
"""


def trunk_pull(context, target):
    if context is None:
        return
    git_home = pathlib.Path(os.environ.get("TIMVISHER_GIT_HOME") or pathlib.Path.home() / "git").resolve()
    worktree = pathlib.Path(context.toplevel).resolve()
    if not worktree.is_relative_to(git_home) or len(worktree.relative_to(git_home).parts) < 3:
        logging.info("Worktree is not under '%s'; not pulling a trunk worktree", git_home)
        return
    org, repo = worktree.relative_to(git_home).parts[:2]
    spec = f"{target.owner}/{target.repo}"
    default = fetch.api(spec, f"repos/{spec}").get("default_branch")
    trunk = git_home / org / repo / default if default else None
    if trunk is None or subprocess.run(["git", "-C", str(trunk), "rev-parse", "--is-inside-work-tree"],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
        logging.info("No trunk worktree at '%s'; not pulling it", trunk)
        return
    log = trunk / ".timvisher_gh" / "trunk-pull.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    aictl.info(code="timvisher_gh_trunk_pull", message=f"Pulling trunk worktree {trunk} in the background (log: {log}).")
    subprocess.Popen(["bash", "-c", TRUNK_PULL, "trunk-pull", str(trunk), str(log), target.pr_url],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def after_merged(opened, context, target, strategy, now):
    with opened.write() as db:
        pr_id = fetch.Fetcher(opened, now).pr(target.owner, target.repo, target.number, conversation=False)
        if strategy:
            store.set_remote(db, pr_id, "merge_strategy", strategy, now)
    trunk_pull(context, target)
    return pr_id


def parse(args):
    target, extra, open_ = None, [], False
    rest = list(args)
    while rest:
        arg = rest.pop(0)
        if arg in ("-h", "--help"):
            sys.stdout.write(USAGE)
            return None
        if arg == "--":
            extra = rest
            break
        if arg == "--open":
            open_ = True
        elif arg == "--no-open":
            open_ = False
        elif arg.startswith("-") or target is not None:
            usage(f"pr merge: unexpected argument '{arg}'", "Pass gh pr merge options after --")
        else:
            target = arg
    return target, extra, open_


def merge(opened, context, found, extra, open_, now, merge_hooks):
    spec = f"{found.owner}/{found.repo}"
    by_comment = comment_merge(spec)
    pull = merge_state(found)
    if pull["state"] == "MERGED":
        commit = (pull.get("mergeCommit") or {}).get("oid")
        aictl.info(code="timvisher_gh_pr_already_merged", message=f"{found.pr_url} is already merged in {commit}.")
        after_merged(opened, context, found, None, now)
        return commit
    if pull["state"] == "CLOSED":
        fail("timvisher_gh_pr_closed", f"{found.pr_url} is closed without merging.",
             suggestions=["Reopen it on GitHub to merge it"])
    if pull["state"] != "OPEN":
        fail("timvisher_gh_pr_unexpected_state", f"{found.pr_url} is in an unexpected state, '{pull['state']}'.")
    reason = requested(pull, by_comment)
    strategy = None
    if reason:
        aictl.info(code="timvisher_gh_merge_requested", message=f"A merge of {found.pr_url} is already requested "
                   f"({reason}); waiting for it.")
    else:
        if not merge_hooks.pre("merge"):
            raise Exit(ERROR)
        strategy = request_by_comment(found) if by_comment else request_by_gh(found, extra)
        if strategy is None:
            raise Exit(ERROR)
    if open_:
        queued = merge_state(found)
        if queued.get("isInMergeQueue") and queued.get("baseRefName"):
            browser.open_tab(f"https://github.com/{spec}/queue/{queued['baseRefName']}")
    commit = wait_until_merged(found)
    aictl.info(code="timvisher_gh_pr_merged", message=f"Merged {found.pr_url} in {commit} via {strategy or reason}.")
    after_merged(opened, context, found, strategy, now)
    return commit


def resolve(opened, context, target):
    found = targets.resolve("pr", target, context=context, db=opened.db, creating=True)
    if found.kind == "source":
        fail("timvisher_gh_pr_missing", f"There's no PR for {found.source} to merge.",
             suggestions=["Create it with 'timvisher_gh pr push'"])
    if found.kind not in nouns.ACCEPTS["pr"]:
        usage(f"'{found.url}' names a {found.kind}, so pr merge can't use it.")
    return found


def hooks_for(opened, context, found, open_, merge_commit=None):
    row = opened.db.execute("SELECT id FROM objects WHERE url = ? COLLATE NOCASE", (found.pr_url,)).fetchone()
    source = store.store_file(opened.db, row[0]) if row else None
    return hooks.Hooks(repo=f"{found.owner}/{found.repo}", worktree=context.toplevel if context else None,
                       pr_url=found.pr_url, open_=open_, merge_commit=merge_commit,
                       title=lambda: pr.parse_source(source.read_text(encoding="utf-8"))["title"]
                       if source is not None and source.exists() else None,
                       state_dir=source.parent if source is not None else None)


def run(context, args):
    parsed = parse(args)
    if parsed is None:
        return 0
    target, extra, open_ = parsed
    opened = state.open_state()
    try:
        store.exporting(opened, lambda object_id: record.record(opened.db, object_id), nouns.now)
        found = resolve(opened, context, target)
        now = nouns.now()
        with opened.write():
            fetch.Fetcher(opened, now).pr(found.owner, found.repo, found.number, conversation=False)
        merge(opened, context, found, extra, open_, now, hooks_for(opened, context, found, open_))
        print(found.pr_url)
        return 0
    except fetch.NotFound as missing:
        fail("timvisher_gh_not_found", f"GitHub has no such PR ({missing}).",
             suggestions=["Check the URL, and that your gh account can see the repository"])
    finally:
        opened.close()
