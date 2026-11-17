import os
import signal
import sys

import functools

from timvisher import aictl
from timvisher.gh import info, nouns, perf, repo
from timvisher.gh.errors import ERROR, Exit, usage

HELP = """\
timvisher_gh - GitHub workflow commands

Usage:
  timvisher_gh [-C <path>] <command> [<args>...]
  timvisher_gh -R OWNER/REPO info [--pr <N>] [--branch <name>] [--json] [<field>]
  timvisher_gh -h | --help | help

Global options (before the command):
  -C <path>              resolve the repository from <path>, not the cwd
  -R, --repo OWNER/REPO  name a repository instead of a worktree; info only.
                         github.com/OWNER/REPO is accepted too.

Commands:
  info [--json]          the whole block as JSON: 'timvisher_git info --json' in a
                         worktree, plus a timvisher_gh object with the fields below.
                         What needs a worktree or a repository is left out without one
  info [--json] <field>  one field; --json prints it as JSON ("x", not x; null
                         prints as an empty line without it). Each is read live
                         from GitHub and needs a repository (a worktree's, or -R):
                           .me                     the GitHub login gh uses for it
                           .exists                 true, or false when GitHub has
                                                   no such repository; the other
                                                   repository fields fail then
                           .archived               true or false
                           .fork                   true or false
                           .parent                 the OWNER/REPO it was forked
                                                   from, or null
                           .defaultBranch          the default branch
                           .permissions.push       whether gh's account can push
                           .topics                 its topics, as a JSON list
                           .forkNetwork.mainRepo   the fork network's root OWNER/REPO
                           .forkNetwork.mainOwner  its owner
                         With --pr <N>, the repository's PR <N>:
                           .pr.head                its head branch
                           .pr.base                its base branch
                           .pr.headRepo            the head branch's OWNER/REPO,
                                                   or null once that's deleted
                           .pr.state               open, closed or merged
                         With --branch <name>, the repository's branch <name>:
                           .branch.exists          true or false
                           .branch.mergedPr        the number of a merged PR from
                                                   a branch of that name, or null
                         --pr and --branch add a pr and a branch object to the
                         block too
  pr info [<target>] [<component>]       a PR's record (see 'pr info --help')
  issue info [<target>] [<component>]    an issue's record
  comment info [<target>] [<component>]  a comment's record
  thread info [<target>] [<component>]   a review thread's record
  review info <target> [<component>]     a review's record

A <target> is a github.com PR, issue, comment or review
(#pullrequestreview-<ID>) URL, current-browser-tab, or a tracked file;
omitted, it comes from the worktree, except for review info, which needs
one.

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
        context = repo.from_worktree(chdir, required=chdir is not None)
    return COMMANDS[command](context, args)


def main(argv):
    perf.start(argv)
    try:
        rc = _run(argv)
    except Exit as stop:
        rc = stop.status
    except KeyboardInterrupt:
        perf.finish(130)
        aictl.notice(code="timvisher_gh_interrupted", message="Interrupted")
        # Die by SIGINT rather than returning 130 so a calling shell loop sees the interrupt and stops too.
        signal.signal(signal.SIGINT, signal.SIG_DFL)
        os.kill(os.getpid(), signal.SIGINT)
        raise
    except BaseException:
        perf.finish(ERROR)
        raise
    perf.finish(rc)
    return rc
