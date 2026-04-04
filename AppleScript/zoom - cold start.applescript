tell application "System Events" to set zoomIsActive to (process "zoom.us" exists)

tell application "zoom.us" to activate

delay 1

tell application "zoom.us" to activate

tell application "System Events"
	tell process "zoom.us"
		if zoomIsActive then
			set t to (time of (current date) as number) + 1
		else
			set t to (time of (current date) as number) + 10
		end if
		set zoomWindowExists to true
		
		repeat until window "Zoom Workplace" exists
			log name of windows as text
			if (time of (current date) as number) is greater than t then
				if zoomIsActive then
					log "Zoom was active and has no windows after delay. Moving on."
					set zoomWindowExists to false
					exit repeat
				else
					display dialog "Zoom window didn't appear in time"
					tell me to error "Zoom window didn't appear in time"
				end if
			end if
			log "Waiting for Zoom window to exist"
			delay 0.5
		end repeat
		
		if zoomWindowExists then
        key code 53
        delay 0.5
        keystroke "w" using {command down}
end if
	end tell
end tell