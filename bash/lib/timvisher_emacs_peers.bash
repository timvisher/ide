#!/usr/bin/env bash

timvisher_emacs_peers__name_re='^[a-z0-9][a-z0-9-]{0,62}$'
timvisher_emacs_peers__max_bytes=65536
timvisher_emacs_peers__ping_timeout=5
timvisher_emacs_peers__send_timeout=60
timvisher_emacs_peers__ls_timeout=10

timvisher_emacs_peers__dir() {
  printf '%s\n' "${TIMVISHER_EMACS_PEERS_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/timvisher/agent-shell/peers.d}"
}

timvisher_emacs_peers__cache_dir() {
  printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/timvisher/agent-shell/peers"
}

timvisher_emacs_peers__now() {
  printf '%s\n' "${TIMVISHER_EMACS_NOW:-$(date +%s)}"
}

timvisher_emacs_peers__self() {
  printf '%s\n' "${TIMVISHER_EMACS_PEER_SELF:-$(hostname -s)}"
}

timvisher_emacs_peers__names() {
  local dir file name
  dir=$(timvisher_emacs_peers__dir)
  for file in "$dir"/*.json
  do
    [[ -f $file ]] || continue
    name=${file##*/}
    name=${name%.json}
    [[ $name =~ $timvisher_emacs_peers__name_re && $name != local ]] || continue
    printf '%s\n' "$name"
  done
}

timvisher_emacs_peers__any() {
  [[ -n $(timvisher_emacs_peers__names) ]]
}

timvisher_emacs_peers__is_peer() {
  local name=$1
  [[ $name =~ $timvisher_emacs_peers__name_re && $name != local ]] || return 1
  [[ -f $(timvisher_emacs_peers__dir)/$name.json ]]
}

# command runs on the remote host, so its ~ is left for the remote shell
# to expand; only the local paths are expanded here.
timvisher_emacs_peers__config() {
  local name=$1 file config
  file=$(timvisher_emacs_peers__dir)/$name.json

  if [[ ! -f $file ]]
  then
    aictl_error \
      --code timvisher_emacs_unknown_peer \
      --message "No peer named '${name}' is configured." \
      --suggestion "List the configured peers with: timvisher_emacs agent-shell peers"
    return 1
  fi

  if ! config=$(jq -ce --arg name "$name" --arg home "$HOME" '
        def tilde: if type == "string" and startswith("~/") then $home + .[1:] else . end;
        def strings: type == "array" and all(.[]; type == "string");
        select(.name == $name)
        | select(.transport == "ssh" or .transport == "socket")
        | select(.transport != "ssh" or ((.host | type) == "string" and 0 < (.host | length)))
        | select(.transport != "socket" or ((.socket | type) == "string" and 0 < (.socket | length)))
        | select(.ssh_options == null or (.ssh_options | strings))
        | select(.probe == null or (.probe | strings))
        | .socket |= tilde
        | .outbox |= tilde
        | .probe |= (if . == null then . else map(tilde) end)
        | .command //= "~/bin/timvisher_emacs"
        | .ssh_options //= []' "$file" 2>/dev/null)
  then
    aictl_error \
      --code timvisher_emacs_bad_peer_config \
      --message "The peer file '${file}' is not a valid peer." \
      --reason "It needs name '${name}' (matching its file name), transport ssh with a host or socket with a socket path, and string arrays for ssh_options and probe." \
      --suggestion "Fix or remove ${file}"
    return 1
  fi
  printf '%s\n' "$config"
}

# US, not TAB: read strips a leading TAB as whitespace, which would turn
# an empty peer field into the session.
timvisher_emacs_peers__split() {
  local address=$1 prefix rest
  if [[ $address == *:* ]]
  then
    prefix=${address%%:*}
    rest=${address#*:}
    if [[ $prefix == local ]]
    then
      printf '\x1f%s\n' "$rest"
      return 0
    fi
    if timvisher_emacs_peers__is_peer "$prefix"
    then
      printf '%s\x1f%s\n' "$prefix" "$rest"
      return 0
    fi
  fi
  printf '\x1f%s\n' "$address"
}

timvisher_emacs_peers__probe() {
  local config=$1
  local -a probe=()
  mapfile -t probe < <(jq -r '(.probe // [])[]' <<< "$config")
  (( 0 == ${#probe[@]} )) && return 0
  "${probe[@]}" > /dev/null 2>&1
}

# One exchange with a socket peer: stdin is the request, stdout the
# whole reply. python3 because neither bash nor macOS's nc can be relied
# on to half-close a Unix socket and then read the answer.
timvisher_emacs_peers__socket_call() {
  local socket=$1 timeout=$2
  python3 -I -c '
import socket, sys
path, timeout = sys.argv[1], float(sys.argv[2])
data = sys.stdin.buffer.read()
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(timeout)
buf = bytearray()
try:
    s.connect(path)
    s.sendall(data)
    s.shutdown(socket.SHUT_WR)
    while True:
        chunk = s.recv(65536)
        if not chunk:
            break
        buf.extend(chunk)
except OSError as e:
    sys.stderr.write(f"{type(e).__name__}: {e}\n")
    sys.exit(1)
sys.stdout.buffer.write(bytes(buf))
' "$socket" "$timeout"
}

# A socket file outlives the forward that made it, and a frozen forward
# accepts and never answers, so only a pong proves the peer is there.
timvisher_emacs_peers__ping() {
  local config=$1 socket reply
  socket=$(jq -r .socket <<< "$config")
  [[ -S $socket ]] || return 1
  reply=$(printf 'X-Agent-Message: 1\nOp: ping\n\n' |
            timvisher_emacs_peers__socket_call "$socket" "$timvisher_emacs_peers__ping_timeout" 2>/dev/null)
  [[ $reply == pong ]]
}

timvisher_emacs_peers__new_id() {
  local now ns
  now=$(date +%s)
  ns=$(date +%N 2>/dev/null)
  [[ $ns =~ ^[0-9]+$ ]] || ns=000000000
  printf '%s.%sP%sR%s.%s\n' "$now" "$ns" "$BASHPID" "$RANDOM" "$(timvisher_emacs_peers__self)"
}

timvisher_emacs_peers__envelope() {
  local to=$1 id=$2 body=$3 hops=${4:-0}
  printf 'X-Agent-Message: 1\nOp: send\nTo: %s\nFrom: %s\nMessage-ID: %s\nDate: %s\nX-Hops: %s\n\n' \
    "$to" "$(timvisher_emacs_peers__self)" "$id" "$(date -R 2>/dev/null || date)" "$hops" &&
    cat -- "$body"
}

timvisher_emacs_peers__is_envelope() {
  local first
  IFS= read -r first < "$1" || return 1
  [[ $first == 'X-Agent-Message: 1' ]]
}

timvisher_emacs_peers__body() {
  awk 'body { print; next } /^$/ { body = 1 }' "$1"
}

timvisher_emacs_peers__outbox_write() {
  local outbox=$1 id=$2 envelope=$3 d
  for d in tmp new cur
  do
    if ! mkdir -p -- "$outbox/$d"
    then
      aictl_error \
        --code timvisher_emacs_outbox_write_failed \
        --message "Cannot create the outbox directory '${outbox}/${d}'."
      return 1
    fi
  done
  if ! cp -- "$envelope" "$outbox/tmp/$id" || ! mv -- "$outbox/tmp/$id" "$outbox/new/$id"
  then
    rm -f -- "$outbox/tmp/$id"
    aictl_error \
      --code timvisher_emacs_outbox_write_failed \
      --message "Cannot write message '${id}' into the outbox '${outbox}'."
    return 1
  fi
}

timvisher_emacs_peers__remote_error() {
  local peer=$1 remote=$2 code message
  code=$(jq -r '.code // "unknown"' <<< "$remote" 2>/dev/null) || code=unknown
  message=$(jq -r '.message // ""' <<< "$remote" 2>/dev/null) || message=$remote
  [[ -n $code ]] || code=unknown
  [[ -n $message ]] || message=$remote
  aictl_error \
    --code timvisher_emacs_peer_error \
    --message "Peer '${peer}' answered ${code}: ${message}" \
    --data "$(jq -cn --arg peer "$peer" --arg code "$code" --arg message "$message" \
                '{peer: $peer, remote_code: $code, remote_message: $message}')"
  return 1
}

timvisher_emacs_peers__unreachable() {
  local peer=$1 reason=$2
  aictl_error \
    --code timvisher_emacs_peer_unreachable \
    --message "Peer '${peer}' is unreachable." \
    --reason "$reason" \
    --suggestion "Check it with: timvisher_emacs agent-shell peers"
  return 1
}

timvisher_emacs_peers__ssh() {
  local config=$1
  shift
  local host
  local -a opts=()
  host=$(jq -r .host <<< "$config")
  mapfile -t opts < <(jq -r '.ssh_options[]' <<< "$config")
  # ssh keeps the first value it sees for an option, so the peer's own
  # ssh_options come first and these are only defaults. ssh reads stdin
  # whether or not the remote command does, so a caller with nothing to
  # send redirects it from /dev/null; inside a loop reading a list, ssh
  # would otherwise swallow the rest of the list.
  ssh -o BatchMode=yes "${opts[@]}" -o ConnectTimeout=5 -- "$host" "$@"
}

timvisher_emacs_peers__send() {
  local peer=$1 session=$2 body=$3 hops=${4:-0}
  local config transport id envelope size
  config=$(timvisher_emacs_peers__config "$peer") || return 1
  transport=$(jq -r .transport <<< "$config")

  if (( 2 <= hops ))
  then
    aictl_error \
      --code timvisher_emacs_peer_loop \
      --message "Not forwarding to '${peer}:${session}': the message has already crossed ${hops} hosts."
    return 1
  fi

  id=$(timvisher_emacs_peers__new_id) || return 1
  envelope=$(mktemp "${TMPDIR:-/tmp}/x.peer-envelope.XXXXXX") || return 1
  local rc=0
  if timvisher_emacs_peers__envelope "$session" "$id" "$body" "$(( hops + 1 ))" > "$envelope"
  then
    timvisher_emacs_peers__send_envelope "$peer" "$config" "$transport" "$session" "$id" "$envelope"
    rc=$?
  else
    rc=1
  fi
  rm -f -- "$envelope"
  return "$rc"
}

timvisher_emacs_peers__send_envelope() {
  local peer=$1 config=$2 transport=$3 session=$4 id=$5 envelope=$6 size
  size=$(wc -c < "$envelope")
  if (( timvisher_emacs_peers__max_bytes < size ))
  then
    aictl_error \
      --code timvisher_emacs_message_too_large \
      --message "The message is ${size// /} bytes; peers take at most ${timvisher_emacs_peers__max_bytes}."
    return 1
  fi

  if ! timvisher_emacs_peers__probe "$config"
  then
    timvisher_emacs_peers__defer_or_fail "$peer" "$config" "$id" "$envelope" "its probe says it is not reachable"
    return
  fi

  case $transport in
    socket)
      timvisher_emacs_peers__send_socket "$peer" "$config" "$id" "$envelope"
      ;;
    ssh)
      timvisher_emacs_peers__send_ssh "$peer" "$config" "$session" "$envelope"
      ;;
  esac
}

timvisher_emacs_peers__defer_or_fail() {
  local peer=$1 config=$2 id=$3 envelope=$4 reason=$5 outbox
  outbox=$(jq -r '.outbox // empty' <<< "$config")
  if [[ -z $outbox ]]
  then
    timvisher_emacs_peers__unreachable "$peer" "$reason"
    return 1
  fi
  timvisher_emacs_peers__outbox_write "$outbox" "$id" "$envelope" || return 1
  aictl_info \
    --code timvisher_emacs_peer_deferred \
    --message "Peer '${peer}' is unreachable (${reason}); the message waits in ${outbox}/new/${id} and goes out when the peer reconnects."
  printf 'deferred\n'
}

timvisher_emacs_peers__send_socket() {
  local peer=$1 config=$2 id=$3 envelope=$4 socket reply status
  socket=$(jq -r .socket <<< "$config")

  if ! timvisher_emacs_peers__ping "$config"
  then
    timvisher_emacs_peers__defer_or_fail "$peer" "$config" "$id" "$envelope" "no answer to ping on ${socket}"
    return
  fi

  # A lost reply after a pong is retried from the outbox with the same
  # Message-ID, and the relay answers duplicate if it had delivered it.
  reply=$(timvisher_emacs_peers__socket_call "$socket" "$timvisher_emacs_peers__send_timeout" < "$envelope" 2>/dev/null)
  IFS= read -r status <<< "$reply"
  case $status in
    submitted|queued|duplicate)
      printf '%s\n' "$status"
      ;;
    error:*)
      timvisher_emacs_peers__remote_error "$peer" "${status#error: }"
      ;;
    *)
      timvisher_emacs_peers__defer_or_fail "$peer" "$config" "$id" "$envelope" "no answer to the send on ${socket}"
      ;;
  esac
}

timvisher_emacs_peers__send_ssh() {
  local peer=$1 config=$2 session=$3 envelope=$4 command out err rc instruction
  command=$(jq -r .command <<< "$config")
  err=$(mktemp "${TMPDIR:-/tmp}/x.peer-ssh-err.XXXXXX") || return 1
  out=$(TIMVISHER_AGENT=1 timvisher_emacs_peers__ssh "$config" \
          "TIMVISHER_AGENT=1 $command agent-shell send $(printf '%q' "$session") -" < "$envelope" 2> "$err")
  rc=$?
  instruction=$(grep -m1 '^{"type":"instruction"' "$err")
  rm -f -- "$err"

  if (( 0 == rc ))
  then
    case $out in
      submitted|queued|duplicate)
        printf '%s\n' "$out"
        return 0
        ;;
    esac
  fi
  if [[ -n $instruction ]]
  then
    timvisher_emacs_peers__remote_error "$peer" "$instruction"
    return 1
  fi
  timvisher_emacs_peers__unreachable "$peer" "ssh exited ${rc} with no answer"
}

timvisher_emacs_peers__fetch() {
  local peer=$1 config transport now listing='' error='' cache old tmp
  now=$(timvisher_emacs_peers__now)
  cache=$(timvisher_emacs_peers__cache_dir)/$peer.json
  mkdir -p -- "${cache%/*}" || return 1

  if ! config=$(timvisher_emacs_peers__config "$peer" 2>/dev/null)
  then
    error='bad or missing peer config'
  elif ! timvisher_emacs_peers__probe "$config"
  then
    error='probe says not reachable'
  else
    transport=$(jq -r .transport <<< "$config")
    case $transport in
      ssh)
        listing=$(timvisher_emacs_peers__ssh "$config" \
                    "$(jq -r .command <<< "$config") agent-shell ls --local --format json" 2>/dev/null < /dev/null) ||
          { listing=''; error='ssh failed'; }
        ;;
      socket)
        if ! timvisher_emacs_peers__ping "$config"
        then
          error='no answer to ping'
        else
          listing=$(printf 'X-Agent-Message: 1\nOp: ls\n\n' |
                      timvisher_emacs_peers__socket_call "$(jq -r .socket <<< "$config")" \
                        "$timvisher_emacs_peers__ls_timeout" 2>/dev/null)
          if [[ ${listing%%$'\n'*} == ok ]]
          then
            listing=${listing#*$'\n'}
          else
            error="ls answered: ${listing%%$'\n'*}"
            listing=''
          fi
        fi
        ;;
    esac
  fi

  if [[ -n $listing ]] && ! jq -e '.sessions | type == "array"' <<< "$listing" > /dev/null 2>&1
  then
    error='listing is not agent-shell ls JSON'
    listing=''
  fi

  old=null
  [[ -f $cache ]] && old=$(jq -c '.listing' "$cache" 2>/dev/null)
  [[ -n $old ]] || old=null

  tmp=$(mktemp "$cache.XXXXXX") || return 1
  if [[ -n $listing ]]
  then
    jq -c --argjson now "$now" '{fetched_at: $now, reachable: true, error: null, listing: .}' <<< "$listing" > "$tmp"
  else
    jq -cn --argjson now "$now" --arg error "$error" --argjson old "$old" \
      '{fetched_at: $now, reachable: false, error: $error, listing: $old}' > "$tmp"
  fi
  mv -f -- "$tmp" "$cache"
}

timvisher_emacs_peers__refresh() {
  local force=${1-} peer cache now ttl fetched
  now=$(timvisher_emacs_peers__now)
  ttl=${TIMVISHER_EMACS_PEER_TTL:-30}
  local -a pids=()
  while IFS= read -r peer
  do
    cache=$(timvisher_emacs_peers__cache_dir)/$peer.json
    if [[ $force != --refresh && -f $cache ]]
    then
      fetched=$(jq -r '.fetched_at // 0' "$cache" 2>/dev/null)
      [[ $fetched =~ ^[0-9]+$ ]] || fetched=0
      (( now - fetched < ttl )) && continue
    fi
    timvisher_emacs_peers__fetch "$peer" &
    pids+=("$!")
  done < <(timvisher_emacs_peers__names)
  (( 0 == ${#pids[@]} )) || wait "${pids[@]}"
}

timvisher_emacs_peers__caches() {
  local peer cache transport
  while IFS= read -r peer
  do
    cache=$(timvisher_emacs_peers__cache_dir)/$peer.json
    transport=$(jq -r '.transport // "?"' "$(timvisher_emacs_peers__dir)/$peer.json" 2>/dev/null)
    if [[ -f $cache ]]
    then
      jq -c --arg name "$peer" --arg transport "$transport" '{name: $name, transport: $transport} + .' "$cache"
    else
      jq -cn --arg name "$peer" --arg transport "$transport" \
        '{name: $name, transport: $transport, reachable: false, error: "never fetched", fetched_at: null, listing: null}'
    fi
  done < <(timvisher_emacs_peers__names) | jq -s .
}

timvisher_emacs_peers__matches() {
  local session=$1
  timvisher_emacs_peers__caches | jq -r --arg s "$session" '
    .[] | select(.reachable) | .name as $peer
    | (.listing.sessions // [])[]
    | select(.session_id == $s or .name == $s or .ref == $s or .address == $s
             or ((.name // "") + " [" + (.ref // "") + "]") == $s)
    | [$peer, (.address // .name // .ref // .session_id)] | @tsv'
}

timvisher_emacs_peers__find() {
  local session=$1 matches
  timvisher_emacs_peers__refresh
  matches=$(timvisher_emacs_peers__matches "$session")
  if [[ -z $matches ]]
  then
    timvisher_emacs_peers__refresh --refresh
    matches=$(timvisher_emacs_peers__matches "$session")
  fi
  [[ -n $matches ]] || return 0

  local -a rows=()
  mapfile -t rows <<< "$matches"
  if (( 1 < ${#rows[@]} ))
  then
    local -a suggestions=()
    local row
    for row in "${rows[@]}"
    do
      suggestions+=(--suggestion "Send to ${row%%$'\t'*}:${row#*$'\t'}")
    done
    aictl_error \
      --code timvisher_emacs_ambiguous_session \
      --message "'${session}' matches ${#rows[@]} sessions on peers." \
      --reason "Bare names resolve only when one host has them." \
      "${suggestions[@]}"
    return 1
  fi
  printf '%s\n' "${rows[0]}"
}

timvisher_emacs_peers__aggregate() {
  local caches
  caches=$(timvisher_emacs_peers__caches)
  jq --argjson peers "$caches" '
    def addr: .address // .name // .ref // .session_id;
    {schema_version: 2,
     sessions: ((.sessions | map(. + {host: null, address: addr}))
                + [$peers[] | select(.reachable) | .name as $p
                   | (.listing.sessions // [])[]
                   | . + {host: ($p + (if .host then ":" + .host else "" end)),
                          address: ($p + ":" + addr)}]),
     unreachable: .unreachable,
     peers: [$peers[] | del(.listing)]}'
}
