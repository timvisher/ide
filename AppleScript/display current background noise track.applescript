set checkVlc to false
set checkSpotify to false

tell application "System Events"
	if 0 is less than (count (application processes whose name is "VLC")) then
		tell application "VLC"
			if playing then
				set checkVlc to true
			end if
		end tell
	end if
	

(*
	if 0 is less than (count (application processes whose name is "Spotify")) then
		tell application "Spotify"
			if playing is player state then
				set checkSpotify to true
			end if
		end tell
	end if
*)
end tell

if checkVlc then
	tell application "VLC"
		if playing then
			display notification "VLC: " & name of current item
		end if
	end tell
end if


(*
if checkSpotify then
	tell application "Spotify"
		if playing is player state then
			display notification "Spotify: " & (name of current track) & " by " & (artist of current track)
		end if
	end tell
end if
*)
