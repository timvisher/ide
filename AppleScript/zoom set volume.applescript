set meetingIsActive to false

if application "zoom.us" is running then
	tell application "System Events" to tell process "zoom.us" to set meetingIsActive to (window "Zoom Meeting" exists) or (window "Zoom Webinar" exists) or (window "Zoom Meeting   40-Minutes" exists)
end if

tell script "Background Noise"
	if not meetingIsActive then
		volumeUp()
	else
		volumeDown()
	end if
end tell
