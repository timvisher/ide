repeat while application "VLC" is running
	try
		delay 0.5
		tell application "VLC" to stop
		delay 0.5
		tell application "VLC" to quit
		delay 0.5
	end try
end repeat

(*
repeat while application "Spotify" is running
	tell application "Spotify" to quit
	delay 0.5
end repeat
*)
