set todoPath to "~/Dropbox/todo/todo.org"
try
	set todoPath to paragraph 1 of (read POSIX file ((POSIX path of (path to home folder)) & ".config/timvisher/ide/AppleScript/config/todo-path"))
end try

tell script "timvisher Terminal" to runCommandInteractively("ntmux todo " & todoPath)
