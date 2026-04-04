on runCommandInteractively(theCommand)
	tell application "Ghostty"
		set c to new surface configuration
		set initial input of c to theCommand & "
"
		new window with configuration c
	end tell
end runCommandInteractively

runCommandInteractively("echo ohai && sleep 5 && exit")

on makeNewWindow()
	tell application "Ghostty"
		new window
	end tell
end makeNewWindow

-- makeNewWindow()

on activateOrMakeNewWindow()
	if application "Ghostty" is not running then
		tell me to makeNewWindow()
		return
	end if
	
	tell application "System Events"
		set visible of application process "Ghostty" to true
		set nonMinimizedWindowCount to count of (windows of application process "Ghostty" whose value of attribute "AXMinimized" is false)
		if 0 is less than nonMinimizedWindowCount then
			tell application "Ghostty" to activate
		else
			tell me to makeNewWindow()
		end if
	end tell
end activateOrMakeNewWindow

--activateOrMakeNewWindow()

on jiggleShellInit()
	tell script "timvisher Terminal" to runCommandInteractively("timvisher_init_clean_refresh")
	repeat while application "Ghostty" is running
		delay 0.5
	end repeat
	delay 1
	tell application "Ghostty" to activate
end jiggleShellInit

on shutdown()
	repeat while application "Ghostty" is running
		tell application "Ghostty" to quit
		delay 0.1
	end repeat
end shutdown