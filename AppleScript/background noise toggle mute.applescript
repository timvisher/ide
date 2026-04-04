tell application "VLC" to set vlcMuted to muted

if vlcMuted then
	run script (POSIX path of (path to home folder) & ".config/timvisher/ide/AppleScript/zoom set volume.applescript")
else
	run script (POSIX path of (path to home folder) & ".config/timvisher/ide/AppleScript/background noise - mute.applescript")
end if

