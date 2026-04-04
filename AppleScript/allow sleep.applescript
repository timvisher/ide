tell application "System Events"
	set nonBackgroundProcesses to displayed name of processes where background only is false
	
	if nonBackgroundProcesses contains "VLC" then
		repeat while 0 < (count of (processes whose name is "VLC"))
			tell application "VLC" to quit
			delay 5
		end repeat
	end if
	
	if nonBackgroundProcesses contains "Screen Sharing" then
		tell application "Screen Sharing" to quit
	end if
	
	if nonBackgroundProcesses contains "myNoise" then
		tell application "myNoise" to quit
	end if
	
	if nonBackgroundProcesses contains "Spotify" then
		tell application "Spotify" to quit
	end if
end tell
