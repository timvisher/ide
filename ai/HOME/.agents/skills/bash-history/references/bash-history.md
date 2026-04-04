# Bash history review

Review command-line activity to understand experiments, tool usage, and operations.

- View today's bash commands (using zsh history timestamps):
  ```bash
  today_start=$(date -d '2025-11-02 00:00:00' +%s)
  today_end=$(date -d '2025-11-03 00:00:00' +%s)
  tail -1000 ~/.bash_history | awk -v start="$today_start" -v end="$today_end" '
    /^#[0-9]+$/ {
      ts = substr($0, 2)
      if (ts >= start && ts < end) {
        cmd_ts = ts
        print_next = 1
      } else {
        print_next = 0
      }
      next
    }
    print_next == 1 {
      "date -d @" cmd_ts " +\"%H:%M:%S\"" | getline time_str
      close("date -d @" cmd_ts " +\"%H:%M:%S\"")
      print time_str "\t" $0
      print_next = 0
    }'
  ```

Bash history notes:
- Zsh history format: `#<unix-timestamp>` followed by command.
- Reveals experimental workflows (multiple iterations on solutions).
- Shows troubleshooting sessions (connectivity tests, queries).
- Captures tool exploration not reflected in commits or scripts.
- Look for patterns: terraform operations, API calls, jq manipulations, parallel processing experiments.
