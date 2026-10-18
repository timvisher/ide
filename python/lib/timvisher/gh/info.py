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
    return _gh("-R", context.spec, "api", "user", "--jq", ".login", failure="Unable to query authenticated user")


def _json(context):
    if context.toplevel is None:
        usage("info --json needs a worktree, since it merges 'timvisher_git info --json'; "
              "-R names only a repository, so query a single field instead")
    done = subprocess.run(["timvisher_git", "info", "--json"], cwd=context.toplevel,
                          stdout=subprocess.PIPE, text=True)
    if done.returncode != 0:
        fail("timvisher_gh_timvisher_git_failed",
             f"Unable to query timvisher_git context for {context.toplevel}",
             suggestions=["Check timvisher_git's error above", "Run 'timvisher_git info --json' there to see it alone"])
    blob = json.loads(done.stdout)
    repo = _repo(context)
    main_repo = _main_repo(context, repo)
    blob["timvisher_gh"] = {
        "me": _me(context),
        "archived": repo.get("archived") is True,
        "forkNetwork": {"mainRepo": main_repo, "mainOwner": main_repo.split("/")[0]},
    }
    return json.dumps(blob, indent=2, ensure_ascii=False)


def field(context, name):
    match name:
        case ".me":
            return _me(context)
        case ".archived":
            return "true" if _repo(context).get("archived") is True else "false"
        case ".forkNetwork.mainRepo":
            return _main_repo(context, _repo(context))
        case ".forkNetwork.mainOwner":
            return _main_repo(context, _repo(context)).split("/")[0]
        case "--json":
            return _json(context)
    usage(f"Unknown info field: '{name}'", f"Fields: {', '.join(FIELDS)}, or --json")


def run(context, args):
    if not args:
        usage("info requires a <field> argument", f"Fields: {', '.join(FIELDS)}, or --json")
    if 1 < len(args):
        name = args[0]
        usage(f"info: unexpected argument '{args[1]}'",
              f"Use 'timvisher_gh -C <path> info {name}' to query another worktree",
              f"Or 'timvisher_gh -R OWNER/REPO info {name}' to query another repository")
    print(field(context, args[0]))
    return 0
