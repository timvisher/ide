tell application "zoom.us" to activate

tell application "System Events"
	
	tell process "zoom.us"
		
		repeat until window "Zoom Meeting" exists
			click menu item "Start Meeting" of menu 1 of menu bar item "Zoom Workplace" of menu bar 1
			delay 1
		end repeat
		
	end tell
	
	run script (POSIX path of (path to home folder) & "/.config/timvisher/ide/AppleScript/zoom set volume.applescript")
end tell