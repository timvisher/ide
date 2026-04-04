tell script "timvisher Terminal" to runCommandInteractively("timvisher_init_clean_refresh")
repeat while application "Ghostty" is running
	delay 0.5
end repeat

tell script "timvisher utilities" to runHomeScript("git/ide/AppleScript/jiggle amethyst.applescript")

set appsToQuit to {Â
	"VLC", Â
	"Screen Sharing", Â
	"Google Chrome", Â
	"Slack", Â
	"zoom.us", Â
	"Calendar", Â
	"Finicky", Â
	"Do Not Disturb while Zoom Sharing", Â
	"Distraction Killer"}


try
	set extraApps to paragraphs of (read POSIX file ((POSIX path of (path to home folder)) & ".config/timvisher/ide/AppleScript/config/good-night-extra-apps"))
	repeat with a in extraApps
		if a as text is not "" then set end of appsToQuit to a as text
	end repeat
end try

repeat with a in appsToQuit
	log a
	repeat while application a is running
		try
			tell application a to quit
		end try
		delay 0.1
	end repeat
end repeat

tell script "timvisher utilities" to runHomeScript("git/ide/AppleScript/ejectDisks.applescript")

tell application "Finder"
	repeat with f in {folder "Downloads" of home, folder "Zoom" of folder "Documents" of home}
		delete every item of f
	end repeat
end tell

tell application "Finder" to close windows

tell application "System Events"
	tell (every process whose name is not "Finder" and visible is not false)
		set visible to false
	end tell
end tell

say "All done!

Good job today, Tim.

Have a great night!

And remember: "

tell script "timvisher utilities" to runHomeScript("git/ide/AppleScript/encourage me.applescript")

tell application "ScreenSaverEngine" to activate

