import json
import subprocess
import sys
import urllib.parse

from timvisher.gh import perf
from timvisher.gh.errors import fail, usage

REPO_FIELDS = (".exists", ".archived", ".fork", ".parent", ".defaultBranch", ".permissions.push", ".topics",
               ".forkNetwork.mainRepo", ".forkNetwork.mainOwner")
PR_FIELDS = (".pr.head", ".pr.base", ".pr.headRepo", ".pr.state")
BRANCH_FIELDS = (".branch.exists", ".branch.mergedPr")
FIELDS = (".me", *REPO_FIELDS, *PR_FIELDS, *BRANCH_FIELDS)


class _Missing(Exception):
    pass


def _gh(*args, failure, missing_ok=False):
    try:
        done = perf.run(["gh", *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    except FileNotFoundError:
        fail("timvisher_gh_gh_missing", f"{failure}: gh is not installed", suggestions=["Install gh, then retry"])
    if done.returncode != 0 and missing_ok and "(HTTP 404)" in done.stderr:
        raise _Missing()
    sys.stderr.write(done.stderr)
    if done.returncode != 0:
        fail("timvisher_gh_gh_failed", failure, suggestions=["Check gh's error above, then retry"])
    return done.stdout.strip()


def _repo(context):
    try:
        raw = json.loads(_gh("api", f"repos/{context.spec}", failure=f"Unable to query repo metadata for {context.spec}",
                             missing_ok=True))
    except _Missing:
        return {"exists": False}
    fork = raw.get("fork") is True
    main_repo = raw["source"]["full_name"] if fork and raw.get("source") else context.spec
    return {
        "exists": True,
        "archived": raw.get("archived") is True,
        "fork": fork,
        "parent": (raw.get("parent") or {}).get("full_name") if fork else None,
        "defaultBranch": raw.get("default_branch"),
        "permissions": {"push": (raw.get("permissions") or {}).get("push") is True},
        "topics": raw.get("topics") or [],
        "forkNetwork": {"mainRepo": main_repo, "mainOwner": main_repo.split("/")[0]},
    }


def _pr(context, number):
    pull = json.loads(_gh("api", f"repos/{context.spec}/pulls/{number}",
                          failure=f"Unable to query PR {context.spec}#{number}"))
    head_repo = (pull["head"].get("repo") or {}).get("full_name")
    return {"head": pull["head"]["ref"], "base": pull["base"]["ref"], "headRepo": head_repo,
            "state": "merged" if pull.get("merged") else pull["state"]}


def _branch_exists(context, name):
    try:
        _gh("api", f"repos/{context.spec}/branches/{urllib.parse.quote(name, safe='')}", "--silent",
            failure=f"Unable to query branch '{name}' of {context.spec}", missing_ok=True)
    except _Missing:
        return False
    return True


def _branch_merged_pr(context, name):
    merged = _gh("-R", context.spec, "pr", "list", "--head", name, "--state", "merged", "--json", "number",
                 "--jq", ".[0].number // empty", failure=f"Unable to list merged PRs for '{name}' in {context.spec}")
    return int(merged) if merged else None


# The gh shim picks the account from the repository, so with none there's no
# login to report rather than whichever account happens to be active.
def _me(context):
    return _gh("-R", context.spec, "api", "user", "--jq", ".login", failure="Unable to query authenticated user")


def _need_repo(context, name):
    if context is None:
        fail("timvisher_gh_no_repository", f"info {name} needs a repository, and this isn't a worktree.",
             suggestions=["Run it in a worktree, or pass -C <worktree>",
                          f"Or name one: 'timvisher_gh -R OWNER/REPO info {name}'"])


def _timvisher_git(context):
    done = perf.run(["timvisher_git", "info", "--json"], cwd=context.toplevel,
                    stdout=subprocess.PIPE, text=True)
    if done.returncode != 0:
        fail("timvisher_gh_timvisher_git_failed",
             f"Unable to query timvisher_git context for {context.toplevel}",
             suggestions=["Check timvisher_git's error above", "Run 'timvisher_git info --json' there to see it alone"])
    return json.loads(done.stdout)


# Fields that need a worktree or a repository are left out without one, rather
# than refusing the whole block.
def _block(context, pr, branch):
    blob = _timvisher_git(context) if context is not None and context.toplevel is not None else {}
    gh = {}
    if context is not None:
        gh["me"] = _me(context)
        gh |= _repo(context)
        if pr is not None:
            gh["pr"] = _pr(context, pr)
        if branch is not None:
            gh["branch"] = {"exists": _branch_exists(context, branch), "mergedPr": _branch_merged_pr(context, branch)}
    blob["timvisher_gh"] = gh
    return blob


def _dig(found, name):
    for key in name[1:].split("."):
        found = found[key]
    return found


def value(context, name, pr=None, branch=None):
    if name not in FIELDS:
        usage(f"Unknown info field: '{name}'", f"Fields: {', '.join(FIELDS)}")
    if name in PR_FIELDS and pr is None:
        usage(f"info {name} needs --pr <number>")
    if name in BRANCH_FIELDS and branch is None:
        usage(f"info {name} needs --branch <name>")
    _need_repo(context, name)
    if name == ".me":
        return _me(context)
    if name in PR_FIELDS:
        return _dig({"pr": _pr(context, pr)}, name)
    if name == ".branch.exists":
        return _branch_exists(context, branch)
    if name == ".branch.mergedPr":
        return _branch_merged_pr(context, branch)
    repo = _repo(context)
    if name != ".exists" and not repo["exists"]:
        fail("timvisher_gh_no_such_repository", f"GitHub has no repository {context.spec}",
             suggestions=["Check the name, and that your gh account can see it",
                          f"'timvisher_gh -R {context.spec} info .exists' answers without failing"])
    return _dig(repo, name)


# null prints as an empty line rather than jq -r's 'null', so a shell caller
# can test the result with [[ -n ]].
def _raw(found):
    if found is None:
        return ""
    if isinstance(found, bool):
        return "true" if found else "false"
    if isinstance(found, (list, dict)):
        return json.dumps(found, ensure_ascii=False)
    return found


def _option(args, flag):
    if not args or not args[0] or args[0].startswith("-"):
        usage(f"info: {flag} requires a value")
    return args.pop(0)


def run(context, args):
    as_json = False
    name = pr = branch = None
    rest = list(args)
    while rest:
        arg = rest.pop(0)
        if arg == "--json":
            as_json = True
        elif arg == "--pr":
            pr = _option(rest, arg)
            if not pr.isdigit():
                usage(f"info: --pr takes a PR number, not '{pr}'")
        elif arg == "--branch":
            branch = _option(rest, arg)
        elif name is None and not arg.startswith("-"):
            name = arg
        else:
            usage(f"info: unexpected argument '{arg}'",
                  f"Use 'timvisher_gh -C <path> info {name or '<field>'}' to query another worktree",
                  f"Or 'timvisher_gh -R OWNER/REPO info {name or '<field>'}' to query another repository")
    if name is None:
        if pr is not None or branch is not None:
            _need_repo(context, "--pr" if pr is not None else "--branch")
        print(json.dumps(_block(context, pr, branch), indent=2, ensure_ascii=False))
        return 0
    found = value(context, name, pr, branch)
    print(json.dumps(found, ensure_ascii=False) if as_json else _raw(found))
    return 0
