tell script "timvisher utilities"
	runHomeScript(".config/timvisher/ide/AppleScript/switch to space 1.applescript")

	runHomeScript(".config/timvisher/ide/AppleScript/good morning - select audio output.applescript")

	runHomeScript(".config/timvisher/ide/AppleScript/jiggle amethyst.applescript")

	-- FIXME Something (probably this) is turning music volume down
	runHomeScript(".config/timvisher/ide/AppleScript/zoom set volume.applescript")

	say "Good morning, Tim!

I hope you have a great day.

And remember: "

	runHomeScript(".config/timvisher/ide/AppleScript/encourage me.applescript")

	tell application "Be Focused Pro" to run

	tell application "Moom Classic" to run

	tell application "Monosnap" to activate

	--tell application "WhichSpace" to run

	tell application "SpaceIndicator" to run

	runHomeScript(".config/timvisher/ide/AppleScript/background media - start.applescript")

	runHomeScript(".config/timvisher/ide/AppleScript/google chrome - cold start.applescript")

	runHomeScript(".config/timvisher/ide/AppleScript/iterm - maybe create todo window.applescript")

	tell application "Do Not Disturb while Zoom Sharing" to run

	tell application "Distraction Killer" to run

	runHomeScript(".config/timvisher/ide/AppleScript/calendar - cold start.applescript")

	say "Let's get to it!"
end tell
