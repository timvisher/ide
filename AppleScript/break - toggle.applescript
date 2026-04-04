tell script "Background Noise" to set muted to isMuted()

if muted then
	set s to ".config/timvisher/ide/AppleScript/break - end.applescript"
else
	set s to ".config/timvisher/ide/AppleScript/break - start.applescript"
end if

tell script "timvisher utilities" to runHomeScript(s)