# Chrome browser activity

Check both open tabs and browsing history to understand research patterns and active work contexts.

- Check all open Chrome tabs across all windows:
  ```bash
  osascript -e 'tell application "Google Chrome"
    set tab_list to {}
    repeat with w in windows
      repeat with t in tabs of w
        set end of tab_list to (URL of t & " | " & title of t)
      end repeat
    end repeat
    return tab_list
  end tell' | tr ',' '\n' | sed 's/^[[:space:]]*//'
  ```
- Check Chrome history across all profiles for a specific date:
  ```bash
  cd "/Users/tim.visher/Library/Application Support/Google/Chrome"
  for history_file in */History
  do
    if [[ -f "$history_file" ]]
    then
      profile=$(dirname "$history_file")
      profile_safe="${profile// /-}"
      # Copy to avoid lock issues
      cp "$history_file" "/tmp/chrome-history-${profile_safe}.db"
      count=$(sqlite3 "/tmp/chrome-history-${profile_safe}.db" \
        "SELECT COUNT(*) FROM urls WHERE date(datetime(last_visit_time/1000000-11644473600, 'unixepoch', 'localtime')) = 'YYYY-MM-DD'" \
        2>/dev/null || echo "0")
      if [[ "$count" -gt 0 ]]
      then
        echo "=== ${profile} ($count URLs) ==="
        sqlite3 "/tmp/chrome-history-${profile_safe}.db" \
          "SELECT url FROM urls WHERE date(datetime(last_visit_time/1000000-11644473600, 'unixepoch', 'localtime')) = 'YYYY-MM-DD'" | \
          awk '
            /amazonaws-us-gov/ {govcloud++}
            /localhost:[0-9]+/ {localhost++}
            /appgate.*\.fed\.d?\.dog|appgate.*gov.*\.d\.dog/ {appgategov++}
            /appgate.*commercial/ {appgatecom++}
            /awsapps\.com/ {awssso++}
            /app\.ddog-gov/ {ddoggov++}
            /app\.datadoghq/ {ddogcom++}
            /datadoghq\.atlassian/ {jira++}
            /github\.com.*\/pull\// {ghpr++}
            /github\.com/ {github++}
            /console\.aws\.amazon/ {awscom++}
            /google\.com/ {google++}
            END {
              if (govcloud > 0) print "  AWS GovCloud Console: " govcloud
              if (awscom > 0) print "  AWS Commercial Console: " awscom
              if (localhost > 0) print "  Localhost OAuth: " localhost
              if (awssso > 0) print "  AWS SSO Portal: " awssso
              if (ddoggov > 0) print "  Datadog GovCloud: " ddoggov
              if (ddogcom > 0) print "  Datadog Commercial: " ddogcom
              if (appgategov > 0) print "  AppGate Gov: " appgategov
              if (appgatecom > 0) print "  AppGate Commercial: " appgatecom
              if (jira > 0) print "  Jira: " jira
              if (ghpr > 0) print "  GitHub PRs: " ghpr
              if (github > 0) print "  GitHub (total): " github
              if (google > 0) print "  Google: " google
            }'
        echo ""
      fi
    fi
  done
  ```

Chrome History notes:
- Chrome uses WebKit/Chromium epoch: microseconds since 1601-01-01, convert with `last_visit_time/1000000-11644473600`.
- Database may be locked while Chrome is running - copy to /tmp first.
- Profile patterns: Profile 1 (general work), Profile 2 (GovCloud monitoring).
- History reveals research patterns, monitoring activity, and access patterns not captured in commits.
