tell application "System Events"
	if (not (application process "Google Chrome" exists)) or 0 is equal to (count of windows of application process "Google Chrome") then
		tell script "Google Chrome" to makeNewProfileWindow("tim.visher@gmail.com")
	end if
end tell

if application "Google Chrome" is running then
	set tryUntil to (current date) + 5
	repeat
		try
			tell application "Google Chrome" to activate
			exit repeat
		end try
		
		if tryUntil is less than (current date) then
			error "Couldn't activate Chrome in time."
		end if
	end repeat
end if
