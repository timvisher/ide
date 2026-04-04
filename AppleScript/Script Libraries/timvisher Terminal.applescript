property currentTerminal : "Ghostty"

on runCommandInteractively(theCommand)
	tell script (currentTerminal of script "timvisher Terminal") to runCommandInteractively(theCommand)
end runCommandInteractively

on makeNewWindow()
	tell script (currentTerminal of script "timvisher Terminal") to makeNewWindow()
end makeNewWindow

on activateOrMakeNewWindow()
	tell script (currentTerminal of script "timvisher Terminal") to activateOrMakeNewWindow()
end activateOrMakeNewWindow

-- makeNewWindow()

on jiggleShellInit()
	tell script (currentTerminal of script "timvisher Terminal") to jiggleShellInit()
end jiggleShellInit

on shutdown()
	tell script (currentTerminal of script "timvisher Terminal") to shutdown()
end shutdown