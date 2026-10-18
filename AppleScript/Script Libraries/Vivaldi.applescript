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

--makeNewProfileWindow("")
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

on waitForTabToLoad(t)
	set deadline to (current date) + 30
	tell application "Vivaldi"
		repeat while loading of t
			if deadline < (current date) then error "Timed out waiting for " & (URL of t) & " to load"
			delay 0.1
		end repeat
	end tell
end waitForTabToLoad

on focusTabWithUrl(u)
	if application "Vivaldi" is not running then
		return false
	end if
	
	tell application "Vivaldi"
		repeat with w in windows
			set i to 0
			repeat with t in tabs of w
				set i to i + 1
				set tabUrl to URL of t
				considering case
					set matched to tabUrl is u or tabUrl is (u & "/")
				end considering
				if matched then
					set active tab index of w to i
					set index of w to 1
					activate
					my waitForTabToLoad(active tab of front window)
					return true
				end if
			end repeat
		end repeat
	end tell
	return false
end focusTabWithUrl

on openTabWithUrl(u)
	tell application "Vivaldi"
		activate
		if (count of windows) is 0 then
			make new window
			set t to active tab of front window
			set URL of t to u
		else
			set t to make new tab at end of tabs of front window with properties {URL:u}
			set active tab index of front window to (count of tabs of front window)
		end if
	end tell
	my waitForTabToLoad(t)
end openTabWithUrl

on closeTabWithUrl(u)
	if application "Vivaldi" is not running then
		return false
	end if
	
	tell application "Vivaldi"
		repeat with w in windows
			repeat with t in tabs of w
				considering case
					if URL of t is u then
						close t
						return true
					end if
				end considering
			end repeat
		end repeat
	end tell
	return false
end closeTabWithUrl
