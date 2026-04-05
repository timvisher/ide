tell application "Image Events"
	if 1 is equal to (count of displays) then
		display notification "only one display. not running relaxation videos"
		return
	end if
end tell

tell application "System Events"
	if 2 is equal to (count (processes whose name is "VLC")) then
		display notification "relaxation videos may already be playing"
		return
	end if
end tell

tell script "Background Noise"
	set currentBackgroundNoise to getCurrentBackgroundNoise()
end tell

-- We only deal with VLC background noise here because we don't quit Spotify to do this
set tryUntil to (current date) + 10
repeat while application "VLC" is running
	try
		tell application "VLC"
			stop
			delay 0.1
			quit
		end tell
	end try
	delay 0.1
	if tryUntil is less than (current date) then
		set m to "VLC failed to quit within 10 seconds. Giving up"
		display notification m
		error m
	end if
end repeat

tell application "System Events"
	if 0 is less than (count of (application processes whose name is "VLC")) then
		set m to "There are open application processes named VLC. Impossible."
		display notification m
		error m
	end if
end tell

try
	tell script "timvisher utilities" to doShellScript({POSIX path of (path to home folder) & "git/ide/bash/bin/timvisher_EXP_relaxation_videos"})
	set tryUntil to (current date) + 10
	tell application "System Events"
		repeat until 0 is less than (count of windows of application process "VLC")
			delay 0.1
			if tryUntil is less than (current date) then
				set m to "VLC failed to create windows in less than 10 seconds. Giving up."
				display notification m
				error m
			end if
		end repeat
	end tell
	delay 0.5
	tell application "VLC" to close (windows whose closeable is true)
on error errStr number errorNumber
	display notification errStr with title "Couldn't start relaxation videos"
	error errStr number errorNumber
end try

tell script "timvisher utilities" to doShellScript({"open", "-a", "VLC", "-n"})

tell application "System Events"
	set tryUntil to (current date) + 10
	repeat until 2 is equal to (count of (application processes whose name is "VLC"))
		delay 0.1
		if tryUntil is less than (current date) then
			set m to "2nd VLC failed to launch in less than 10 seconds. Giving up."
			display notification m
			error m
		end if
	end repeat
	
	set tryUntil to (current date) + 10
	repeat until 1 is equal to (count of (windows of item -1 of (application processes whose name is "VLC")))
		delay 0.1
		if tryUntil is less than (current date) then
			set m to "2nd VLC failed to show a window in less than 10 seconds. Giving up"
			display notification m
			error m
		end if
	end repeat
end tell

tell application "System Events"
	if false then
		-- Something about this seems to force 'application "VLC"' to stick to the original process. I'm not sure why.
		set tryUntil to (current date) + 10
		repeat until 0 is equal to (count of (windows of item -1 of (application processes whose name is "VLC")))
			tell application "VLC" to close windows
			if tryUntil is less than (current date) then
				set m to "Failed to close all closeable VLC windows in less than 10 seconds. Giving up"
				display notification m
				error m
			end if
			delay 0.1
		end repeat
	else
		set visible of item -1 of (application processes whose name is "VLC") to false
	end if
end tell

tell script "timvisher utilities"
	if currentBackgroundNoise is not missing value then
		if currentBackgroundNoise contains "VLC: " then
			if currentBackgroundNoise contains "music_for_programming" then
				runHomeScript("background noise - music for programming.applescript")
			else if currentBackgroundNoise contains "dronezone" then
				runHomeScript("background noise - dronezone.applescript")
			else if currentBackgroundNoise contains "groovesalad" then
				runHomeScript("background noise - groovesalad.applescript")
			end if
		end if
	end if
end tell