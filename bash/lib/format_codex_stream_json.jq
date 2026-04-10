# Format codex exec --json JSONL events into readable progress lines.
# Usage: jq --unbuffered -r --arg tz_offset "$(date +%z)" -f format_codex_stream_json.jq

def ts:
  now | strftime("%FT%T") + $tz_offset;

def pad_right(n):
  (. + (" " * n))[:n];

# Indent continuation lines so multiline content aligns with the content column.
def align(n):
  gsub("\n"; "\n" + (" " * n));

# Prefix layout: ts(24) + " type  "(7) + name(12) + " "(1) = 44.
def align: align(44);

.item as $item
| if .type == "thread.started" then
    "\(ts) start thread \(.thread_id // "")"
  elif .type == "turn.started" then
    "\(ts) turn  started"
  elif .type == "item.started" then
    if $item.type == "command_execution" then
      "\(ts) cmd   \("started" | pad_right(12)) \($item.command // "" | align)"
    else empty
    end
  elif .type == "item.completed" then
    if $item.type == "command_execution" then
      "\(ts) cmd   \("done" | pad_right(12)) \($item.command[:80] // "" | align)"
    elif $item.type == "reasoning" then
      # ts(24) + " think "(7) = 31
      "\(ts) think \($item.text // "" | align(31))"
    elif $item.type == "agent_message" then
      # ts(24) + " text  "(7) = 31
      "\(ts) text  \($item.text // "" | align(31))"
    else empty
    end
  elif .type == "turn.completed" then
    (.usage // {}) as $u
    | "\(ts) done  in=\($u.input_tokens // 0) cached=\($u.cached_input_tokens // 0) out=\($u.output_tokens // 0)"
  else empty
  end
