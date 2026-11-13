on makeNewProfileWindow(profileIdentifier)
	makeNewProfile2 given profileIdentifier:profileIdentifier
end makeNewProfileWindow

-- makeNewProfileWindow("")

on makeNewProfile2 given profileIdentifier:profileIdentifier : "", URL:urlArg : ""
	set commandList to {POSIX path of (path to home folder) & "bin/chrome_new_profile_window"}
	if (profileIdentifier as text) contains "@" then
		set end of commandList to profileIdentifier
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

--makeNewProfileWindow("")
--makeNewProfile2 given profileIdentifier:""
--makeNewProfile2 given profileIdentifier:"user@example.com"
-- The following doesn't work because AppleScript. When a handler uses given you must pass at least one argument using given to get any of the defaults
-- makeNewProfile2()

on getTabWithUrl(u)
	if application "Google Chrome" is not running then
		return missing value
	end if
	
	tell application "Google Chrome"
		repeat with wRef in (get windows)
			set t to missing value
			try
				set t to get (first tab whose URL is u) of (contents of wRef)
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
	tell application "Google Chrome"
		repeat while loading of t
			if deadline < (current date) then error "Timed out waiting for " & (URL of t) & " to load"
			delay 0.1
		end repeat
	end tell
end waitForTabToLoad

-- Windows come from (get windows), which returns id references, and tabs
-- are addressed by id. Not "repeat with w in windows": it re-resolves
-- "item N of every window" by z-order on each pass, so it fails or lands
-- on the wrong window when tabs or windows change mid-scan.

on isGoneError(n)
	return n is in {-1719, -1728}
end isGoneError

on tabIdWithUrl(w, u, orWithSlash)
	tell application "Google Chrome"
		repeat 3 times
			try
				set tabIds to id of tabs of w
				set tabUrls to URL of tabs of w
			on error m number n
				if my isGoneError(n) then return missing value
				error m number n
			end try
			if (count of tabIds) is (count of tabUrls) then
				repeat with i from 1 to count of tabIds
					set tabUrl to item i of tabUrls
					considering case
						set matched to tabUrl is u or (orWithSlash and tabUrl is (u & "/"))
					end considering
					if matched then return item i of tabIds
				end repeat
				return missing value
			end if
		end repeat
	end tell
	return missing value
end tabIdWithUrl

-- The browser's tabs have no index property and a tab can only be made
-- active by its position, so the position is looked up from the tab's id
-- right before it is set, and checked afterwards.
on activateTab(w, tabId)
	tell application "Google Chrome"
		repeat 3 times
			try
				set tabIds to id of tabs of w
				if tabIds does not contain tabId then return false
				repeat with i from 1 to count of tabIds
					if item i of tabIds is tabId then exit repeat
				end repeat
				set active tab index of w to i
				if id of active tab of w is tabId then return true
			on error m number n
				if my isGoneError(n) then return false
				error m number n
			end try
		end repeat
	end tell
	return false
end activateTab

on focusTabWithUrl(u)
	if application "Google Chrome" is not running then
		return false
	end if
	
	tell application "Google Chrome" to set ws to get windows
	repeat with wRef in ws
		set w to contents of wRef
		set tabId to my tabIdWithUrl(w, u, true)
		if missing value is not tabId and my activateTab(w, tabId) then
			tell application "Google Chrome"
				set index of w to 1
				activate
				set t to tab id tabId of w
			end tell
			my waitForTabToLoad(t)
			return true
		end if
	end repeat
	return false
end focusTabWithUrl

on openTabWithUrl(u)
	tell application "Google Chrome"
		activate
		if (count of windows) is 0 then
			set w to make new window
			set t to active tab of w
			set URL of t to u
		else
			set w to window id (id of front window)
			set t to make new tab at end of tabs of w with properties {URL:u}
			my activateTab(w, id of t)
		end if
	end tell
	my waitForTabToLoad(t)
end openTabWithUrl

on closeTabWithUrl(u)
	if application "Google Chrome" is not running then
		return false
	end if
	
	tell application "Google Chrome" to set ws to get windows
	repeat with wRef in ws
		set w to contents of wRef
		set tabId to my tabIdWithUrl(w, u, false)
		if missing value is not tabId then
			try
				tell application "Google Chrome" to close tab id tabId of w
				return true
			on error m number n
				if not my isGoneError(n) then error m number n
			end try
		end if
	end repeat
	return false
end closeTabWithUrl
