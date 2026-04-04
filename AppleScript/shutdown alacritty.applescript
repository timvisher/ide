tell application "System Events"
	repeat while 0 < (count of (processes whose name is "Alacritty"))
		tell application "Alacritty" to quit
		delay 0.5
	end repeat
end tell
