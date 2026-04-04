# Format claude --output-format stream-json events into readable progress lines.
# Usage: jq --unbuffered -r --arg tz_offset "$(date +%z)" -f format_stream_json.jq

def ts:
  now | strftime("%FT%T") + $tz_offset;

def pad_right(n):
  (. + (" " * n))[:n];

# Indent continuation lines so multiline content aligns with the content column.
def align(n):
  gsub("\n"; "\n" + (" " * n));

# Prefix layout: ts(24) + " type  "(7) + name(12) + " "(1) = 44.
def align: align(44);

def tool_summary:
  .message.content[0].input
  | if .file_path then .file_path
    elif .command then .command[:120]
    elif .pattern then .pattern
    elif .query then .query
    elif .prompt then .prompt[:80] + "..."
    elif .description then .description
    else tostring[:100]
    end // empty;

.message.content[0] as $block
| if .type == "assistant" then
    if $block.type == "tool_use" then
      "\(ts) tool  \($block.name | pad_right(12)) \(tool_summary | align)"
    elif $block.type == "text" then
      # ts(24) + " text  "(7) = 31
      ($block.text // "") | if . != "" then "\(ts) text  \(. | align(31))" else empty end
    else empty
    end
  elif .type == "system" then
    if .subtype == "task_progress" then
      "\(ts) agent \(.last_tool_name // "" | pad_right(12)) \(.description // "" | align)"
    elif .subtype == "task_started" then
      # ts(24) + " agent started: "(16) = 40
      "\(ts) agent started: \(.description // "" | align(40))"
    elif .subtype == "task_notification" then
      (.status // "") as $s
      # ts(24) + " agent "(7) + status + ": "(2)
      | "\(ts) agent \($s): \(.summary // "" | align(24 + 7 + ($s | length) + 2))"
    else empty
    end
  elif .type == "result" then
    (if .duration_ms then "\(.duration_ms / 1000 | floor)s" else "" end) as $dur
    | "\(ts) done  \(.num_turns // "") turns, $\(.total_cost_usd // ""), \($dur)"
  else empty
  end
