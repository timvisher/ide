# low-disk plugin protocol

`scripts/low-disk` finds plugins, runs them, and merges what they print.
Everything about a disk consumer — what exists, how big it is, whether it
is safe to reclaim — lives in its plugin.

## Discovery

A plugin is an executable file. `low-disk` loads every executable in:

1. `scripts/plugins/` in this skill (general plugins, ide repo)
2. `${XDG_CONFIG_HOME:-~/.config}/timvisher/ide/low-disk/plugins/`
   (machine- or employer-specific plugins, such as the system extensions
   repo)

The file name is the plugin name. Only names of lowercase letters, digits
and dashes (`^[a-z0-9][a-z0-9-]*$`) are loaded, so editor backups and
`x.`/`y.`/`z.` scratch scripts sitting in a plugin directory are ignored.
The same name in both directories is an error.

## Interface

A plugin is called with one subcommand and prints exactly one JSON object
on stdout. Logs and diagnostics go to stderr. A non-zero exit means the plugin
failed.

### `measure`

Report what exists and how much disk it uses:

```json
{"targets": {"<target>": {"bytes": 123, "path": "/some/path"}}}
```

`<target>` is whatever the plugin needs to identify the thing again in
`reclaim`. `bytes` is the disk it uses. Any other fields are the plugin's
own; add them when something reads them.

### `reclaim <target>...`

Reclaim the named targets and report what happened to each, keyed the same
way. The plugin decides whether each target is safe to reclaim and refuses
the ones that are not, saying why:

```json
{"targets": {"<target>": {"reclaimed": false, "reason": "..."}}}
```

## Environment

`low-disk` exports `LOW_DISK`, the path to itself, so a plugin can call
back into it. Plugins that need it should refuse to run without it.

## Activity

`low-disk activity` prints every timvisher_git worktree with what it knows
about whether it is in use:

```json
{"worktrees": {"/path/to/worktree": {
  "repo": "org/repo",
  "protected": false,
  "attached": true,
  "sessions": [{"name": "org/repo/branch", "attached": true}]
}}}
```

- `attached`: a tmux client is attached to a session in the worktree right
  now. That is the strongest sign Tim is using it; never reclaim from an
  attached worktree.
- `protected`: `timvisher_dev_ci worktrees active` lists it. Without
  `timvisher_dev_ci` installed nothing is protected.
- `sessions`: tmux sessions with the worktree as their path or a pane whose
  current directory is in it, attached or not, on every socket in
  `${TMUX_TMPDIR:-/tmp}/tmux-$UID/`. A session in a worktree nested inside
  another counts for both.

`activity` fails rather than guess: when a tmux socket refuses the
connection, the socket directory cannot be read, tmux prints something it
cannot parse, or `timvisher_dev_ci` fails. A stale socket (no server behind it) just has no sessions.

Until something records detach times, "no client attached right now" is
the only idle signal.

## Sizes

`low-disk size <path>...` sizes paths for plugins, in parallel, staying on
each path's filesystem:

```json
{"sizes": {"/some/path": {"bytes": 123, "incomplete": false, "device": 16777232}}}
```

`incomplete` is true when part of the tree could not be read, so `bytes`
is a lower bound; a missing path has `"bytes": null`. `device` is the
filesystem the path is on.

## What low-disk adds

- `low-disk measure [<plugin>...]` prints
  `{"plugins": {"<plugin>": <its measure output>}}`.
- `low-disk reclaim <plugin>:<target>...` groups targets by plugin, calls
  each plugin's `reclaim` once, and prints the same `{"plugins": ...}` shape.
- A plugin that exits non-zero or prints anything other than exactly one
  JSON object is reported as `{"plugins": {"<plugin>": {"error": "..."}}}`.
  The other plugins still report, and `low-disk` exits non-zero.

## Working with no free space

The point of these tools is to run when the disk is full, so the code in
`low-disk` and its plugins does not intentionally write to disk: no temp
files, no heredocs or here-strings (bash may back them with temp files), no
caches. Pass data through pipes and command substitution. Deleting things
is the only disk activity, and it is assumed to work.

This is a principle for this code, not a guarantee about the commands it
runs: `timvisher_dev_ci`, `tmux` and the plugins' own tools are outside it.

## Bundled plugins

- `worktrees`: timvisher_git worktrees (bare and not-yet-migrated caches)
  with their activity and size. A worktree nested in another on the same
  filesystem is counted only in itself. Refuses every reclaim: removing
  worktrees is `timvisher_git worktree gc`'s job, in an agent session.
- `biggest`: every directory directly under `$HOME` and
  `/private/var/tmp`, largest first, so you can spot what no plugin covers.
  `LOW_DISK_BIGGEST_ROOTS` replaces those roots with a colon-separated list
  (empty means the defaults). Loose files, symlinks and mount points are
  skipped; a root that cannot be listed fails the plugin. Refuses every
  reclaim.
