tell application "System Events"
	if 1 is less than (count (processes whose name is "VLC")) then
		log "Assuming relaxation videos are playing"
		set targetVlcCount to 1
	else
		set targetVlcCount to 0
	end if
	
	set attempts to 0
	set maxAttempts to 20
	repeat until targetVlcCount = (count (processes whose name is "VLC"))
		tell application "VLC" to quit
		if maxAttempts is less than attempts then
			display notification "VLC failed to quit after 10 seconds"
			error "VLC failed to quit after 10 seconds"
		else
			set attempts to attempts + 1
			log "Still waiting"
			delay 0.5
		end if
	end repeat
	
	tell script "timvisher utilities" to doShellScript({"open", "-a", "VLC", "-n"})
	
	set attempts to 0
	set maxAttempts to 20
	repeat until (targetVlcCount + 1) = (count (processes whose name is "VLC"))
		if maxAttempts is less than attempts then
			display notification "VLC failed to restart after 10 seconds"
			error "VLC failed to restart after 10 seconds"
		end if
	end repeat
end tell