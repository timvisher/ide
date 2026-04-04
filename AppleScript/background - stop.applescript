tell application "System Events"
	repeat while (count of (application processes whose name is "VLC")) is not 0
		try
			tell application "VLC"
				stop
				delay 0.5
				quit
			end tell
		on error
			display notification "Unable to quit VLC"
		end try
	end repeat
end tell

tell application "Spotify" to quit