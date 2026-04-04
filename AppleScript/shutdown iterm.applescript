tell application "System Events"
	repeat while 0 < (count of (processes whose name is "iTerm2"))
		tell application "iTerm"
			close windows
			quit
		end tell
		delay 0.5
	end repeat
end tell
