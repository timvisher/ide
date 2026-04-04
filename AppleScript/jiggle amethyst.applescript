if application "Amethyst" is running then
	tell application "Amethyst" to quit
end if

set tryUntil to (current date) + 10
repeat while application "Amethyst" is running
	delay 0.1
	log "Waiting for Amethyst to quit"
	if tryUntil is less than (current date) then
		set m to "Amethyst didn't quit in 10 seconds. Giving up"
		display dialog m
		error m
	end if
end repeat

tell application "Amethyst" to activate