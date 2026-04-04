on getActiveTabUrl()
	if application "Google Chrome" is not running then
		set msg to "Google Chrome is not running. No active tab to get"
		display dialog msg
		error msg
	end if
	tell application "Google Chrome" to get URL of active tab of front window
end getActiveTabUrl

-- getActiveTabUrl()

on getActiveTabYtDlpUrl()
	tell script "timvisher utilities" to doShellScript({¬
		POSIX path of (path to home folder) & "bin/chrome_js_in_active_tab", ¬
		POSIX path of (path to home folder) & "bin/chrome_js/yt-dlp-url.js"})
end getActiveTabYtDlpUrl

on makeNewProfileWindow(email)
	makeNewProfile2 given email:email
end makeNewProfileWindow

-- makeNewProfileWindow given email:""

on makeNewProfile2 given email:email : "", URL:urlArg : ""
	set commandList to {POSIX path of (path to home folder) & "bin/chrome_new_profile_window"}
	if (email as text) contains "@" then
		set end of commandList to email
	end if
	if urlArg is not "" then
		set end of commandList to urlArg
	end if
	tell script "timvisher utilities" to doShellScript(commandList)
	
	set maxWindowCreationTime to (current date) + 10
	
	set m to "Unable to create window in time"
	repeat while application "Google Chrome" is not running
		if maxWindowCreationTime < (current date) then
			display notification m
			error m
		end if
		log "Waiting for Google Chrome to be running"
		delay 1
	end repeat
	
	delay 1
	
	tell application "System Events"
		repeat while 0 is equal to (count of windows of application process "Google Chrome")
			if maxWindowCreationTime < (current date) then
				display notification m
				error m
			end if
			log "Waiting for the window to be created"
			delay 1
		end repeat
	end tell
	
	delay 1
end makeNewProfile2

makeNewProfileWindow("")
--makeNewProfile2 given email:""
--makeNewProfile2 given email:"user@example.com"
-- The following doesn't work because AppleScript. When a handler uses given you must pass at least one argument using given to get any of the defaults
-- makeNewProfile2()

on getTabWithUrl(u)
	if application "Google Chrome" is not running then
		return missing value
	end if
	
	tell application "Google Chrome"
		repeat with w in windows
			set t to missing value
			try
				set t to get (first tab whose URL is u) of w
			end try
			if missing value is not t then
				exit repeat
			end if
		end repeat
		
		t
	end tell
end getTabWithUrl

-- getTabWithUrl("https://www.youtube.com/@PogoMusic")