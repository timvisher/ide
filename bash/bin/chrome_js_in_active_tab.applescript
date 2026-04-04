on run argv
	tell application "Google Chrome" to execute active tab of front window javascript (read (open for access (POSIX path of (item 1 of argv))))
end run