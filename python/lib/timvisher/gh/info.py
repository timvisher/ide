import json
import subprocess

from timvisher.gh.errors import fail, usage

FIELDS = (".me", ".archived", ".forkNetwork.mainRepo", ".forkNetwork.mainOwner")


def _gh(*args, failure):
    done = subprocess.run(["gh", *args], stdout=subprocess.PIPE, text=True)
    if done.returncode != 0:
        fail("timvisher_gh_gh_failed", failure, suggestions=["Check gh's error above, then retry"])
    return done.stdout.strip()


def _repo(context):
    out = _gh("api", f"repos/{context.spec}", "--jq", "{fork, source: .source.full_name, archived}",
              failure=f"Unable to query repo metadata for {context.spec}")
    return json.loads(out)


def _main_repo(context, repo):
    if repo.get("fork") is True and repo.get("source") is not None:
        return repo["source"]
    return context.spec


def _me(context):
    repo_args = ["-R", context.spec] if context is not None else []
    return _gh(*repo_args, "api", "user", "--jq", ".login", failure="Unable to query authenticated user")


def _need_repo(context, name):
    if context is None:
        fail("timvisher_gh_no_repository", f"info {name} needs a repository, and this isn't a worktree.",
             suggestions=["Run it in a worktree, or pass -C <worktree>",
                          f"Or name one: 'timvisher_gh -R OWNER/REPO info {name}'"])


def _timvisher_git(context):
    done = subprocess.run(["timvisher_git", "info", "--json"], cwd=context.toplevel,
                          stdout=subprocess.PIPE, text=True)
    if done.returncode != 0:
        fail("timvisher_gh_timvisher_git_failed",
             f"Unable to query timvisher_git context for {context.toplevel}",
             suggestions=["Check timvisher_git's error above", "Run 'timvisher_git info --json' there to see it alone"])
    return json.loads(done.stdout)


# Fields that need a worktree or a repository are left out without one, rather
# than refusing the whole block.
def _block(context):
    blob = _timvisher_git(context) if context is not None and context.toplevel is not None else {}
    gh = {"me": _me(context)}
    if context is not None:
        repo = _repo(context)
        main_repo = _main_repo(context, repo)
        gh["archived"] = repo.get("archived") is True
        gh["forkNetwork"] = {"mainRepo": main_repo, "mainOwner": main_repo.split("/")[0]}
    blob["timvisher_gh"] = gh
    return blob


def value(context, name):
    if name == ".me":
        return _me(context)
    if name not in FIELDS:
        usage(f"Unknown info field: '{name}'", f"Fields: {', '.join(FIELDS)}")
    _need_repo(context, name)
    repo = _repo(context)
    match name:
        case ".archived":
            return repo.get("archived") is True
        case ".forkNetwork.mainRepo":
            return _main_repo(context, repo)
        case ".forkNetwork.mainOwner":
            return _main_repo(context, repo).split("/")[0]


def _raw(found):
    if isinstance(found, bool):
        return "true" if found else "false"
    return found


def run(context, args):
    as_json = False
    name = None
    for arg in args:
        if arg == "--json":
            as_json = True
        elif name is None and not arg.startswith("-"):
            name = arg
        else:
            usage(f"info: unexpected argument '{arg}'",
                  f"Use 'timvisher_gh -C <path> info {name or '<field>'}' to query another worktree",
                  f"Or 'timvisher_gh -R OWNER/REPO info {name or '<field>'}' to query another repository")
    if name is None:
        print(json.dumps(_block(context), indent=2, ensure_ascii=False))
        return 0
    found = value(context, name)
    print(json.dumps(found, ensure_ascii=False) if as_json else _raw(found))
    return 0
