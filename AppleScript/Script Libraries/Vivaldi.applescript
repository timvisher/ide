on getActiveTabUrl()
	if application "Vivaldi" is not running then
		set msg to "Vivaldi is not running. No active tab to get"
		display dialog msg
		error msg
	end if
	tell application "Vivaldi" to get URL of active tab of front window
end getActiveTabUrl

-- getActiveTabUrl()

on getActiveTabYtDlpUrl()
	tell script "timvisher utilities" to doShellScript({¬
		POSIX path of (path to home folder) & "bin/vivaldi_js_in_active_tab", ¬
		POSIX path of (path to home folder) & "bin/browser_js/yt-dlp-url.js"})
end getActiveTabYtDlpUrl

on makeNewProfileWindow(profileIdentifier)
	makeNewProfile2 given profileIdentifier:profileIdentifier
end makeNewProfileWindow

-- makeNewProfileWindow("")

on makeNewProfile2 given profileIdentifier:profileIdentifier : "", URL:urlArg : ""
	set commandList to {POSIX path of (path to home folder) & "bin/vivaldi_new_profile_window"}
	if (profileIdentifier as text) is not "" then
		set end of commandList to profileIdentifier
	end if
	if urlArg is not "" then
		set end of commandList to urlArg
	end if
	tell script "timvisher utilities" to doShellScript(commandList)

	set maxWindowCreationTime to (current date) + 10

	set m to "Unable to create window in time"
	repeat while application "Vivaldi" is not running
		if maxWindowCreationTime < (current date) then
			display notification m
			error m
		end if
		log "Waiting for Vivaldi to be running"
		delay 1
	end repeat

	delay 1

	tell application "System Events"
		repeat while 0 is equal to (count of windows of application process "Vivaldi")
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
--makeNewProfile2 given profileIdentifier:""
--makeNewProfile2 given profileIdentifier:"Personal"
-- The following doesn't work because AppleScript. When a handler uses given you must pass at least one argument using given to get any of the defaults
-- makeNewProfile2()

on getTabWithUrl(u)
	if application "Vivaldi" is not running then
		return missing value
	end if

	tell application "Vivaldi"
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
