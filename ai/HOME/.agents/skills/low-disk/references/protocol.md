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

The file name is the plugin name. A name may not contain `:`, and the same
name in both directories is an error.

## Interface

A plugin is called with one subcommand and prints a single JSON object on
stdout. Logs and diagnostics go to stderr. A non-zero exit means the plugin
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

## What low-disk adds

- `low-disk measure [<plugin>...]` prints
  `{"plugins": {"<plugin>": <its measure output>}}`.
- `low-disk reclaim <plugin>:<target>...` groups targets by plugin, calls
  each plugin's `reclaim` once, and prints the same `{"plugins": ...}` shape.
- A plugin that exits non-zero or prints something other than a JSON
  object is reported as `{"<plugin>": {"error": "..."}}`. The other plugins
  still report, and `low-disk` exits non-zero.

## Working with no free space

The point of these tools is to run when the disk is full, so neither
`low-disk` nor its plugins intentionally write to disk: no temp files, no
heredocs or here-strings (bash may back them with temp files), no caches.
Pass data through pipes and command substitution. Deleting things is the
only disk activity, and it is assumed to work.
