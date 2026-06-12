# shellcheck disable=SC1090
source ~/.functions/logging.bash ||
  {
    echo "Unable to source logging functions" >&2
    exit 1
  }

export TIMVISHER_AGENT=1

agents_bash=${XDG_CONFIG_HOME:-${HOME}/.config}/timvisher/ide/ai/agents.bash
if [[ -r $agents_bash ]]
then
  # shellcheck disable=SC1090
  source "$agents_bash"
else
  info '%s not found' "$agents_bash"
fi

# Resolve the Anthropic API base URL so callers can gate connectivity
# without hardcoding the endpoint. Claude Code exposes no command to print
# its resolved config, so we read the one place the gateway is ever set:
# the org-managed settings file (.env.ANTHROPIC_BASE_URL). Falls back to an
# exported ANTHROPIC_BASE_URL. Prints the URL and returns 0 when one is
# found; prints nothing and returns 1 otherwise (no override, or no jq).
timvisher_anthropic_resolve_base_url() {
  local managed="/Library/Application Support/ClaudeCode/managed-settings.json"

  if command -v jq >/dev/null 2>&1 && [[ -r $managed ]]
  then
    local url
    url=$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "$managed" 2>/dev/null)
    if [[ -n $url ]]
    then
      trace 'anthropic base url: "%s" (from managed settings)' "$url"
      printf '%s' "$url"
      return 0
    fi
  fi

  if [[ -n ${ANTHROPIC_BASE_URL:-} ]]
  then
    trace 'anthropic base url: "%s" (from environment)' "$ANTHROPIC_BASE_URL"
    printf '%s' "$ANTHROPIC_BASE_URL"
    return 0
  fi

  trace 'anthropic base url: no override configured'
  return 1
}

# Block until the resolved Anthropic endpoint is reachable, delegating the
# actual host:port check to timvisher_wait_for_connectivity. Skips
# silently when that waiter is unavailable, when no endpoint is configured,
# or when TIMVISHER_SKIP_CONNECTIVITY_GATE is set. Override the overall
# timeout (seconds) with TIMVISHER_CONNECTIVITY_GATE_TIMEOUT.
timvisher_anthropic_connectivity_gate() {
  if [[ -n ${TIMVISHER_SKIP_CONNECTIVITY_GATE:-} ]]
  then
    trace 'connectivity gate: skipped (TIMVISHER_SKIP_CONNECTIVITY_GATE set)'
    return 0
  fi

  if ! command -v timvisher_wait_for_connectivity >/dev/null 2>&1
  then
    trace 'connectivity gate: timvisher_wait_for_connectivity unavailable, skipping'
    return 0
  fi

  local url
  url=$(timvisher_anthropic_resolve_base_url) ||
    {
      trace 'connectivity gate: no endpoint resolved, skipping'
      return 0
    }

  # Split host[:port] out of the resolved URL, defaulting the port from the
  # scheme, so we can hand them to the connectivity waiter.
  local hostport=${url#*://}
  hostport=${hostport%%/*}
  local host port
  case $hostport in
    *:*)
      host=${hostport%%:*}
      port=${hostport##*:}
      ;;
    *)
      host=$hostport
      case $url in
        http://*)
          port=80
          ;;
        *)
          port=443
          ;;
      esac
      ;;
  esac

  local -a gate_args=("$host" "$port")
  if [[ -n ${TIMVISHER_CONNECTIVITY_GATE_TIMEOUT:-} ]]
  then
    gate_args+=("$TIMVISHER_CONNECTIVITY_GATE_TIMEOUT")
  fi

  trace 'connectivity gate: waiting for "%s:%s"' "$host" "$port"
  if timvisher_wait_for_connectivity "${gate_args[@]}"
  then
    return 0
  fi

  die 'connectivity gate: cannot reach Anthropic endpoint "%s". Check VPN/gateway connectivity, or set TIMVISHER_SKIP_CONNECTIVITY_GATE=1 to bypass.' "$url"
}

