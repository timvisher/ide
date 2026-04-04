if application "Google Chrome" is running then
	tell application "Google Chrome" to activate
end if

tell application "System Events"
	if (not (application process "Google Chrome" exists)) or 0 is equal to (count of windows of application process "Google Chrome") then
		tell script "Google Chrome" to makeNewProfileWindow("")
	end if
end tell
