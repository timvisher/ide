import sys

import functools

from timvisher.gh import info, nouns, repo
from timvisher.gh.errors import Exit, usage

HELP = """\
timvisher_gh - GitHub workflow commands

Usage:
  timvisher_gh [-C <path>] <command> [<args>...]
  timvisher_gh -R OWNER/REPO info <field>
  timvisher_gh -h | --help | help

Global options (before the command):
  -C <path>              resolve the repository from <path>, not the cwd
  -R, --repo OWNER/REPO  name a repository instead of a worktree; info only.
                         github.com/OWNER/REPO is accepted too.

Commands:
  info <field>  print one repository field:
                  .me                     the authenticated GitHub login
                  .archived               true or false
                  .forkNetwork.mainRepo   the fork network's root OWNER/REPO
                  .forkNetwork.mainOwner  its owner
  info --json   'timvisher_git info --json' plus a timvisher_gh object with
                those fields; needs a worktree
  pr info [<target>] [<component>]       a PR's record (see 'pr info --help')
  issue info [<target>] [<component>]    an issue's record
  comment info [<target>] [<component>]  a comment's record
  thread info [<target>] [<component>]   a review thread's record

A <target> is a github.com PR, issue or comment URL, current-browser-tab,
or a tracked file; omitted, it comes from the worktree.

Exit status: 0 success, 1 error, 2 usage.
"""

COMMANDS = {"info": info.run} | {noun: functools.partial(nouns.run, noun) for noun in nouns.NOUNS}


def _parse_globals(argv):
    chdir = repo_option = None
    while argv:
        match argv[0]:
            case "-C":
                if len(argv) < 2:
                    usage("Option -C requires a <path> argument")
                if not argv[1]:
                    usage("Option -C requires a non-empty <path> argument")
                chdir, argv = argv[1], argv[2:]
            case "-R" | "--repo" as flag:
                if len(argv) < 2:
                    usage(f"Option {flag} requires an OWNER/REPO argument")
                if not argv[1]:
                    usage(f"Option {flag} requires a non-empty OWNER/REPO argument")
                repo_option, argv = argv[1], argv[2:]
            case _:
                break
    return chdir, repo_option, argv


def _run(argv):
    chdir, repo_option, argv = _parse_globals(argv)
    if not argv:
        sys.stderr.write(HELP)
        usage("timvisher_gh needs a command")
    command, args = argv[0], argv[1:]
    if command in ("-h", "--help", "help"):
        sys.stdout.write(HELP)
        return 0
    if chdir is not None and repo_option is not None:
        usage("Options -C and -R are mutually exclusive: -C names a worktree, -R names a repository")
    if repo_option is not None and command != "info":
        usage(f"Option -R is only supported with 'info'; '{command}' needs a worktree (use -C)")
    if command not in COMMANDS:
        sys.stderr.write(HELP)
        usage(f"Unknown command: '{command}'")
    if repo_option is not None:
        context = repo.from_option(repo_option)
    else:
        context = repo.from_worktree(chdir)
    return COMMANDS[command](context, args)


def main(argv):
    try:
        return _run(argv)
    except Exit as stop:
        return stop.status
