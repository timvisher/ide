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

on tabIds()
	set ids to {}
	if application "Vivaldi" is not running then
		return ids
	end if
	
	tell application "Vivaldi"
		repeat with w in windows
			set ids to ids & (id of tabs of w)
		end repeat
	end tell
	return ids
end tabIds

-- A tab is found by its id not being in knownIds rather than by its
-- URL alone: SSO and other redirects change the URL while it loads.
-- The URL only picks between several new tabs, e.g. when Vivaldi
-- restores a session as it starts. With several new tabs and none
-- matching, no tab is safe to claim.
on newTab(u, knownIds)
	if application "Vivaldi" is not running then
		return missing value
	end if
	
	tell application "Vivaldi"
		set newTabs to {}
		repeat with w in windows
			set windowId to id of w
			set windowTabIds to id of tabs of w
			repeat with tabIdRef in windowTabIds
				set tabId to contents of tabIdRef
				if knownIds does not contain tabId then
					set t to tab id tabId of window id windowId
					set tabUrl to URL of t
					considering case
						set matched to tabUrl is u or tabUrl is (u & "/")
					end considering
					if matched then
						return t
					end if
					set end of newTabs to t
				end if
			end repeat
		end repeat
		if 1 is (count of newTabs) then
			return item 1 of newTabs
		end if
	end tell
	return missing value
end newTab

-- `open location` outside any tell, not a new tab made in Vivaldi's
-- front window: the default URL handler (Finicky) picks the browser
-- and profile. Vivaldi runs every profile in one process, so the tab
-- shows up here whichever profile Finicky picks. When Finicky picks
-- another app, no tab shows up: return false rather than error,
-- since the URL did open.
on openTabWithUrl(u)
	set knownIds to my tabIds()
	open location u
	set deadline to (current date) + 10
	repeat
		set t to my newTab(u, knownIds)
		if t is not missing value then
			my waitForTabToLoad(t)
			return true
		end if
		if deadline < (current date) then
			return false
		end if
		delay 0.1
	end repeat
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
