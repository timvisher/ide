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

