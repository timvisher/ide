# Format gemini -o stream-json events into readable progress lines.
# Usage: jq --unbuffered -r --arg tz_offset "$(date +%z)" -f format_gemini_stream_json.jq

def ts:
  now | strftime("%FT%T") + $tz_offset;

def pad_right(n):
  (. + (" " * n))[:n];

# Indent continuation lines so multiline content aligns with the content column.
def align(n):
  gsub("\n"; "\n" + (" " * n));

# Prefix layout: ts(24) + " type  "(7) + name(12) + " "(1) = 44.
def align: align(44);

if .type == "init" then
  "\(ts) start session \(.session_id // "") model=\(.model // "")"
elif .type == "message" then
  if .role == "user" then
    empty
  else
    # ts(24) + " text  "(7) = 31
    (.content // "") | if . != "" then "\(ts) text  \(. | align(31))" else empty end
  end
elif .type == "tool_use" then
  "\(ts) tool  \(.tool_name // "" | pad_right(12)) \(.parameters | if .file_path then .file_path elif .command then .command[:120] elif .pattern then .pattern elif .query then .query else tostring[:100] end // "" | align)"
elif .type == "tool_result" then
  "\(ts) tool  \("done" | pad_right(12)) \(.tool_id // "") status=\(.status // "")"
elif .type == "result" then
  (.stats // {}) as $s
  | "\(ts) done  in=\($s.input_tokens // 0) out=\($s.output_tokens // 0) cached=\($s.cached // 0) \(($s.duration_ms // 0) / 1000 | floor)s"
else empty
end
