#!/usr/bin/env bash

# aictl config - Layered config merge for AI clients
#
# Merges per-tool config across three layers (later wins):
#   target  ←  base (~/git/ide)  ←  overlay (~/.config/timvisher/ide)
#
# The "target" layer (whatever already exists at the destination)
# preserves runtime-managed state — Codex's [projects.*] trust-level
# entries, Claude's enabledPlugins state, etc. — without us having to
# enumerate which keys are runtime-managed.
#
# Provides:
#   aictl_config_update [tool...]   Regen merged config for tool(s); default: all
#   aictl_config_show <tool>        Print merged result without writing
#   aictl_config_paths <tool>       Print base/overlay/target paths
#   aictl_config_tools              List configured tools
#
# Idempotent and atomic. Safe to call from shim startup AND by hand.
#
# Tooling: dasel for TOML <-> JSON conversion (because yq's TOML output
# is broken for quoted keys like [projects."/path"]). jq for the actual
# deep-merge. Both formats use the same merge primitive.

source ~/.functions/logging.bash ||
  {
    echo "Unable to source logging functions" >&2
    return 1 2>/dev/null || exit 1
  }

if [[ -z ${_aictl_loaded:-} ]]
then
  source ~/.functions/aictl.bash ||
    {
      echo "Unable to source aictl functions" >&2
      return 1 2>/dev/null || exit 1
    }
fi

_aictl_config_loaded=true

# Registry: emits one TSV row per tool.
# Columns: <name>\t<format>\t<base>\t<overlay>\t<target>
#
# Format is "toml" or "json". Paths must be absolute. Missing base or
# overlay files are silently skipped during merge — only target is
# required to be writable (its parent dir is created if needed).
aictl_config_targets() {
  local ide_home=${HOME}/git/ide
  local dd_home=${XDG_CONFIG_HOME:-${HOME}/.config}/timvisher/ide

  printf 'codex\ttoml\t%s\t%s\t%s\n' \
    "${ide_home}/ai/codex/config.toml" \
    "${dd_home}/ai/codex/config.toml" \
    "${HOME}/.codex/config.toml"

  printf 'claude\tjson\t%s\t%s\t%s\n' \
    "${ide_home}/ai/claude/HOME/.claude/settings.json" \
    "${dd_home}/ai/claude/HOME/.claude/settings.json" \
    "${HOME}/.claude/settings.json"
}

# List configured tool names, one per line.
aictl_config_tools() {
  aictl_config_targets | cut -f1
}

# Look up registry row for a single tool. Sets globals:
#   _aictl_config_format, _aictl_config_base, _aictl_config_overlay, _aictl_config_target
# Returns 1 if tool is unknown.
aictl_config__lookup() {
  local tool=$1
  local row name
  while IFS=$'\t' read -r name _aictl_config_format _aictl_config_base _aictl_config_overlay _aictl_config_target
  do
    if [[ $name == "$tool" ]]
    then
      return 0
    fi
  done < <(aictl_config_targets)

  aictl_error \
    --code "aictl_config_unknown_tool" \
    --message "Unknown tool '${tool}'. Run 'aictl config tools' to see configured tools." \
    --suggestion "aictl config tools"
  return 1
}

# Convert one source file to JSON, write to stdout. Format inferred from
# arg. Returns 0 with empty output if file does not exist.
aictl_config__to_json() {
  local format=$1 path=$2
  if [[ ! -r $path ]]
  then
    return 0
  fi
  case $format in
    toml)
      dasel query -i toml -o json --root < "$path" || return 1
      ;;
    json)
      cat "$path" || return 1
      ;;
    *)
      aictl_error \
        --code "aictl_config_unknown_format" \
        --message "Unknown format '${format}' for ${path}"
      return 1
      ;;
  esac
}

# Convert merged JSON (on stdin) back to the target format, write to
# stdout.
aictl_config__from_json() {
  local format=$1
  case $format in
    toml)
      dasel query -i json -o toml --root || return 1
      ;;
    json)
      jq '.' || return 1
      ;;
    *)
      aictl_error \
        --code "aictl_config_unknown_format" \
        --message "Unknown format '${format}'"
      return 1
      ;;
  esac
}

# Compute merged content for a tool and write to stdout.
aictl_config__merge_to_stdout() {
  local tool=$1
  aictl_config__lookup "$tool" || return 1

  local format=$_aictl_config_format
  local layers=("$_aictl_config_target" "$_aictl_config_base" "$_aictl_config_overlay")

  local acc='{}' layer_json
  local layer
  for layer in "${layers[@]}"
  do
    layer_json=$(aictl_config__to_json "$format" "$layer") || return 1
    if [[ -n $layer_json ]]
    then
      acc=$(jq -n --argjson a "$acc" --argjson b "$layer_json" '$a * $b') || return 1
    fi
  done

  printf '%s' "$acc" | aictl_config__from_json "$format"
}

# Print merged content for a tool to stdout. Does not modify target.
aictl_config_show() {
  if (( $# != 1 ))
  then
    aictl_error \
      --code "aictl_config_show_arity" \
      --message "Usage: aictl config show <tool>"
    return 1
  fi
  aictl_config__merge_to_stdout "$1"
}

# Print base/overlay/target paths for a tool.
aictl_config_paths() {
  if (( $# != 1 ))
  then
    aictl_error \
      --code "aictl_config_paths_arity" \
      --message "Usage: aictl config paths <tool>"
    return 1
  fi
  aictl_config__lookup "$1" || return 1
  printf 'format:  %s\n' "$_aictl_config_format"
  printf 'base:    %s\n' "$_aictl_config_base"
  printf 'overlay: %s\n' "$_aictl_config_overlay"
  printf 'target:  %s\n' "$_aictl_config_target"
}

# Regenerate merged config for a single tool, atomic write to target.
# Replaces a symlink target with a regular file (Claude's settings.json
# currently symlinks straight to the overlay; first run breaks the link).
aictl_config__update_one() {
  local tool=$1
  aictl_config__lookup "$tool" || return 1

  local target=$_aictl_config_target
  local target_dir
  target_dir=$(dirname "$target")
  mkdir -p "$target_dir" || return 1

  local tmp="${target}.tmp.$$"
  if ! aictl_config__merge_to_stdout "$tool" > "$tmp"
  then
    rm -f "$tmp"
    return 1
  fi

  # If target is a symlink, remove it before mv so we replace the link
  # itself, not what it points at. (Initial state for ~/.claude/settings.json.)
  if [[ -L $target ]]
  then
    rm -f "$target" || { rm -f "$tmp"; return 1; }
  fi

  mv "$tmp" "$target" || { rm -f "$tmp"; return 1; }
}

# Regenerate merged config for one or more tools (default: all).
aictl_config_update() {
  local tools=()
  if (( $# == 0 ))
  then
    while IFS= read -r t
    do
      tools+=("$t")
    done < <(aictl_config_tools)
  else
    tools=("$@")
  fi

  local tool rc=0
  for tool in "${tools[@]}"
  do
    if ! aictl_config__update_one "$tool"
    then
      rc=1
    fi
  done
  return $rc
}
