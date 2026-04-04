# Git commits (daily review)

- `git log --since/--until` uses author date by default, not committer date.
- After rebasing, commits have new committer dates but keep original author dates.
- Pure git cannot filter by author date in a range - must use grep.
- To see commits authored on a specific date:
  ```bash
  git log --format="%ai %s" | grep "^YYYY-MM-DD"
  ```
- To count commits from a specific day:
  ```bash
  git log --format="%ai %s" | grep "^YYYY-MM-DD" | wc -l
  ```
- Example for 2025-10-30:
  ```bash
  git log --format="%ai %s" | grep "^2025-10-30"
  ```
- If you have multiple active repos (from the `active-work-context` skill), run the same query in each repo:
  ```bash
  repos=(
    "/path/to/repo1"
    "/path/to/repo2"
  )
  for repo in "${repos[@]}"
  do
    echo "== $repo =="
    git -C "$repo" log --format="%ai %s" | grep "^YYYY-MM-DD"
  done
  ```
- Note: `git reflog` shows actual commit operations (including rebases) but is less useful for summarizing logical work done.
- See: https://stackoverflow.com/questions/37311494/how-to-get-git-to-show-commits-in-a-specified-date-range-for-author-date
