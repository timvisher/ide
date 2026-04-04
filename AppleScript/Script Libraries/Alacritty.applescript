on runCommandInteractively(theCommand)
	if application "Alacritty" is running then
		tell application "Alacritty" to activate
	end if
	
	set countWindows to 0
	try
		tell application "System Events" to set countWindows to count windows of application process "Alacritty"
	end try
	
	tell script "timvisher utilities" to doShellScript({POSIX path of (path to home folder) & "bin/run_alacritty"})
	
	tell application "System Events"
		set tryUntil to (current date) + 10
		repeat
			try
				if countWindows is less than (count windows of application process "Alacritty") then
					exit repeat
				end if
			end try
			
			if tryUntil is less than (current date) then
				set m to "Alacritty window did not appear in 10 seconds"
				display notification m
				error m
			end if
		end repeat
		
		tell application process "Alacritty"
			keystroke (theCommand as text)
			keystroke return
		end tell
	end tell
end runCommandInteractively

-- runCommandInteractively("ntmux todo ~/Documents/example/todo.org")

-- runCommandInteractively("nohup jiggle_shell_init & tail -F nohup.out")

on makeNewWindow()
	tell application "Alacritty" to activate
	tell script "timvisher utilities" to doShellScript({POSIX path of (path to home folder) & "bin/run_alacritty"})
end makeNewWindow

on activateOrMakeNewWindow()
	if application "Alacritty" is running then
		tell application "System Events"
			set visible of application process "Alacritty" to true
			delay 0.1
		end tell
	end if
	
	tell application "Alacritty" to activate
	tell application "System Events"
		if 0 is equal to (count of windows of application process "Alacritty") then
			tell me to makeNewWindow()
		end if
	end tell
end activateOrMakeNewWindow

-- activateOrMakeNewWindow()