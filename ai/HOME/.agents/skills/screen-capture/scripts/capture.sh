#!/usr/bin/env bash
# capture.sh — capture all macOS displays at full resolution to a
# timestamped subdirectory under ~/Pictures/agent screen captures/.
#
# Writes a .cookie file with session metadata for later cross-analysis.
# On success, emits a structured aictl_info instruction to stderr listing
# the produced paths so the invoking agent can Read them. On failure,
# emits aictl_die with a code and suggestions.
#
# Diagnostic per-step output goes through logging.bash (info/error),
# which auto-emits structured JSON when running under an agent.

set -uo pipefail

source ~/.functions/aictl.bash ||
  {
    echo "aictl unavailable; cannot emit structured output" >&2
    exit 1
  }
source ~/.functions/logging.bash ||
  {
    aictl_die --code "logging_unavailable" --message "logging.bash failed to source"
  }

# Treat agent context broadly — TIMVISHER_AGENT gates structured-JSON
# logging, but CLAUDECODE/TIMVISHER_CODEX are equivalent triggers in
# practice. Promote them so info/warn/error emit JSON.
if [[ -z ${TIMVISHER_AGENT:-} ]] && [[ -n ${CLAUDECODE:-} || -n ${TIMVISHER_CODEX:-} ]]
then
  export TIMVISHER_AGENT=1
fi

base_dir="${HOME}/Pictures/agent screen captures"
ts=$(date +"%Y-%m-%dT%H-%M-%S%z")
out_dir="${base_dir}/${ts}"

mkdir -p "${out_dir}" ||
  aictl_die \
    --code "capture_mkdir_failed" \
    --message "Could not create capture directory '${out_dir}'" \
    --suggestion "Check ~/Pictures permissions and free space"
info "created capture directory: '%s'" "${out_dir}"

# Cache `system_profiler SPDisplaysDataType` once — it costs 1–3s on a
# cold call and we use it twice (display count + cookie metadata).
sp_displays=$(system_profiler SPDisplaysDataType 2>/dev/null) || sp_displays=""

# Count connected displays. Each display reports a 'Resolution:' line
# in the modern macOS output. If Apple changes that format in a future
# release this will need to move to JSON parsing (system_profiler -json),
# but for the supported macOS range a single Resolution: per display is
# the documented shape.
display_count=$(printf '%s\n' "${sp_displays}" | grep -c "Resolution:") || display_count=0
if (( display_count < 1 ))
then
  aictl_die \
    --code "no_displays_detected" \
    --message "system_profiler reported zero displays" \
    --reason "screencapture needs at least one display attached" \
    --suggestion "Confirm at least one monitor is connected and powered on"
fi

info "detected %s display(s)" "${display_count}"

# Build one output path per display. screencapture writes display N to
# the Nth path argument.
paths=()
for ((i=1; i <= display_count; i++))
do
  paths+=("${out_dir}/screen-${i}.png")
done

# No -x: the shutter sound plays so the user hears the capture happen.
if ! screencapture "${paths[@]}"
then
  aictl_die \
    --code "screencapture_failed" \
    --message "screencapture exited non-zero capturing ${display_count} display(s)" \
    --suggestion "Verify Screen Recording permission for the agent host in System Settings → Privacy & Security → Screen Recording" \
    --suggestion "If permission is granted but PNGs are still black, restart the parent process so the new permission takes effect"
fi

# Sanity check: a file under 1KB indicates total capture failure (the
# OS can also return zero with an empty PNG when permission is missing
# and content protection is on). Detecting "all-black PNG" specifically
# would need histogram analysis (sips/ImageMagick); a size floor catches
# the empty/near-empty case without that dependency.
for p in "${paths[@]}"
do
  if [[ ! -f $p ]] || (( $(stat -c %s -- "$p" 2>/dev/null || stat -f %z -- "$p" 2>/dev/null || echo 0) < 1024 ))
  then
    aictl_die \
      --code "screencapture_likely_blocked" \
      --message "screencapture exited zero but '${p}' is missing or under 1KB — capture appears blocked or empty" \
      --reason "Screen Recording permission can be missing in a way that produces empty or near-empty PNGs with a zero exit code" \
      --suggestion "Grant Screen Recording permission to the agent host in System Settings → Privacy & Security → Screen Recording" \
      --suggestion "Restart the parent process after granting permission so the change takes effect"
  fi
done

# Cookie file — session-of-origin breadcrumbs for cross-analysis.
cookie_file="${out_dir}/.cookie"
{
  printf 'timestamp_slug: %s\n' "${ts}"
  printf 'iso8601: %s\n' "$(date -Iseconds 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S%z")"
  printf 'user: %s\n' "${USER:-unknown}"
  printf 'host: %s\n' "$(hostname)"
  printf 'cwd: %s\n' "${PWD}"
  printf 'shell_pid: %s\n' "$$"
  printf 'parent_pid: %s\n' "${PPID}"
  printf 'parent_cmd: %s\n' "$(ps -o command= -p "${PPID}" 2>/dev/null || printf 'unknown')"
  printf 'display_count: %s\n' "${display_count}"
  printf '\n'

  # CLAUDE_* prefix-match alone does NOT guarantee non-secret values
  # (e.g. CLAUDE_API_KEY would slip through), so a denylist of common
  # secret-bearing suffixes is layered on top before persisting.
  printf '# Claude env vars (CLAUDE_* prefix; secret-bearing names denied)\n'
  claude_env=$(env | grep -E "^CLAUDE" | grep -Eiv '(KEY|TOKEN|SECRET|PASSWORD|PASSPHRASE|AUTH|CREDENTIAL|COOKIE|SESSION_TOKEN)' || true)
  if [[ -n "${claude_env}" ]]
  then
    printf '%s\n' "${claude_env}"
  else
    printf '(none)\n'
  fi
  printf '\n'

  printf '# Terminal session IDs\n'
  printf 'TERM_SESSION_ID: %s\n' "${TERM_SESSION_ID:-(unset)}"
  printf 'ITERM_SESSION_ID: %s\n' "${ITERM_SESSION_ID:-(unset)}"
  printf '\n'

  # Display info: the indent-prefix branch matches display headers as
  # emitted by `system_profiler SPDisplaysDataType`. Format drift across
  # macOS versions falls into the (unavailable) branch — informational
  # only, so a graceful no-match is acceptable.
  printf '# Display info\n'
  display_info=$(printf '%s\n' "${sp_displays}" | grep -E "(^        [A-Z]|Resolution:|Display Type:)" || true)
  if [[ -n "${display_info}" ]]
  then
    printf '%s\n' "${display_info}"
  else
    printf '(unavailable)\n'
  fi
  printf '\n'

  printf '# Files\n'
  # shellcheck disable=SC2012  # human-readable listing for the cookie
  ls -lh "${out_dir}"/*.png 2>/dev/null
} > "${cookie_file}"

# Build aictl_info suggestions: one Read instruction per file plus the
# cookie pointer. The agent consumes these as the next-step list.
suggestion_args=()
for p in "${paths[@]}"
do
  suggestion_args+=(--suggestion "Read '${p}' to view the captured image")
done
suggestion_args+=(--suggestion "Cookie metadata at '${cookie_file}' — session-of-origin breadcrumbs for cross-analysis")

aictl_info \
  --code "screen_capture_complete" \
  --message "Captured ${display_count} display(s) to '${out_dir}'. Read each PNG and describe what is relevant to the user's request." \
  "${suggestion_args[@]}"

# Also print the directory on stdout so non-aictl-aware callers can
# parse it. The structured payload on stderr is the primary channel
# for agents.
printf '%s\n' "${out_dir}"
