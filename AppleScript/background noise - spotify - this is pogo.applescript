(*
set backgroundNoiseChoices to {}

set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:37i9dQZF1DZ06evO0KP33w", "Spotify Playlist: This is Pogo"}

log backgroundNoiseChoices

set backgroundNoiseChoice to some item of backgroundNoiseChoices

display notification "Playing " & item 3 of backgroundNoiseChoice
log backgroundNoiseChoice

if item 1 of backgroundNoiseChoice is "spotify" then
	tell application "VLC"
		stop
	end tell
	tell application "Spotify"
		play track item 2 of backgroundNoiseChoice
		repeat while player state is not playing
			delay 0.5
			set sound volume to 47
			set repeating to true
			set shuffling to true
			play track item 2 of backgroundNoiseChoice
		end repeat
	end tell
else if item 1 of backgroundNoiseChoice is "applescript" then
	run script item 2 of backgroundNoiseChoice
	tell application "Spotify"
		pause
	end tell
	tell application "VLC"
		set audio volume to 160
	end tell
else
	msg = "Bad entry in backgroundNoiseChoices" & backgroundNoiseChoice
	display dialog msg
	error msg
end if
*)
