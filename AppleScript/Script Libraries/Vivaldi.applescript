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

-- System Events rather than Vivaldi's own windows, which include every
-- Space's: only the windows on this Space can be seen.
on visibleWindows()
	if application "Vivaldi" is not running then
		return {}
	end if
	
	tell application "System Events"
		return windows of application process "Vivaldi" whose subrole is "AXStandardWindow" and value of attribute "AXMinimized" is false
	end tell
end visibleWindows

on activateOrMakeNewWindow()
	set ws to my visibleWindows()
	if 0 is (count of ws) then
		my makeNewProfileWindow("")
		return
	end if
	
	tell application "System Events" to perform action "AXRaise" of item 1 of ws
	tell application "Vivaldi" to activate
end activateOrMakeNewWindow

-- activateOrMakeNewWindow()

on getTabWithUrl(u)
	if application "Vivaldi" is not running then
		return missing value
	end if
	
	tell application "Vivaldi"
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
	tell application "Vivaldi"
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
	tell application "Vivaldi"
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
	tell application "Vivaldi"
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
	if application "Vivaldi" is not running then
		return false
	end if
	
	tell application "Vivaldi" to set ws to get windows
	repeat with wRef in ws
		set w to contents of wRef
		set tabId to my tabIdWithUrl(w, u, true)
		if missing value is not tabId and my activateTab(w, tabId) then
			tell application "Vivaldi"
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

on tabIds()
	set ids to {}
	if application "Vivaldi" is not running then return ids
	tell application "Vivaldi" to set ws to get windows
	repeat with wRef in ws
		set w to contents of wRef
		try
			tell application "Vivaldi" to set ids to ids & (id of tabs of w)
		on error m number n
			if not my isGoneError(n) then error m number n
		end try
	end repeat
	return ids
end tabIds

-- A tab is found by its id not being in knownIds rather than by its
-- URL alone: SSO and other redirects change the URL while it loads.
-- The URL only picks between several new tabs, e.g. when Vivaldi
-- restores a session as it starts. With several new tabs and none
-- matching, no tab is safe to claim.
on newTab(u, knownIds)
	if application "Vivaldi" is not running then return missing value
	set newTabs to {}
	tell application "Vivaldi" to set ws to get windows
	repeat with wRef in ws
		set w to contents of wRef
		tell application "Vivaldi"
			repeat 3 times
				try
					set windowTabIds to id of tabs of w
					set windowTabUrls to URL of tabs of w
				on error m number n
					if my isGoneError(n) then exit repeat
					error m number n
				end try
				if (count of windowTabIds) is (count of windowTabUrls) then
					repeat with i from 1 to count of windowTabIds
						set tabId to item i of windowTabIds
						if knownIds does not contain tabId then
							set tabUrl to item i of windowTabUrls
							considering case
								set matched to tabUrl is u or tabUrl is (u & "/")
							end considering
							if matched then return tab id tabId of w
							set end of newTabs to tab id tabId of w
						end if
					end repeat
					exit repeat
				end if
			end repeat
		end tell
	end repeat
	if 1 is (count of newTabs) then return item 1 of newTabs
	return missing value
end newTab

-- Through openUrl, not a new tab made in Vivaldi's front window:
-- the default URL handler (Finicky) picks the browser and profile.
-- Vivaldi runs every profile in one process, so the tab shows up
-- here whichever profile Finicky picks. When Finicky picks another
-- app, no tab shows up: return false rather than error, since the URL
-- did open.
on openTabWithUrl(u)
	set knownIds to my tabIds()
	tell script "timvisher Browser" to openUrl(u)
	set deadline to (current date) + 10
	repeat
		set t to my newTab(u, knownIds)
		if t is not missing value then
			my waitForTabToLoad(t)
			return true
		end if
		if deadline < (current date) then return false
		delay 0.1
	end repeat
end openTabWithUrl

on closeTabWithUrl(u)
	if application "Vivaldi" is not running then
		return false
	end if
	
	tell application "Vivaldi" to set ws to get windows
	repeat with wRef in ws
		set w to contents of wRef
		set tabId to my tabIdWithUrl(w, u, false)
		if missing value is not tabId then
			try
				tell application "Vivaldi" to close tab id tabId of w
				return true
			on error m number n
				if not my isGoneError(n) then error m number n
			end try
		end if
	end repeat
	return false
end closeTabWithUrl

on windowWithTabId(tabId)
	tell application "Vivaldi" to set ws to get windows
	repeat with wRef in ws
		set w to contents of wRef
		try
			tell application "Vivaldi" to set tabIds to id of tabs of w
			if tabIds contains tabId then return w
		on error m number n
			if not my isGoneError(n) then error m number n
		end try
	end repeat
	return missing value
end windowWithTabId

on executeJsInTabWithId(tabId, js)
	-- Not "as integer": tab ids pass AppleScript's integer range (2^29) and
	-- become reals that match no tab. The browser reports them as text.
	set tabId to tabId as text
	if application "Vivaldi" is not running then error "Vivaldi is not running." number -600
	set w to my windowWithTabId(tabId)
	if missing value is w then error "Vivaldi has no tab with id " & tabId & "." number -1728
	tell application "Vivaldi" to execute tab id tabId of w javascript js
end executeJsInTabWithId

-- One record per tab, fields separated by character id 31 and records by
-- character id 30: window id, tab id, whether it is its window's active
-- tab, URL, title. Not linefeeds or tabs: titles can contain either.
on listTabs()
	if application "Vivaldi" is not running then return ""
	set tabRecords to {}
	tell application "Vivaldi" to set ws to get windows
	repeat with wRef in ws
		set w to contents of wRef
		tell application "Vivaldi"
			repeat 3 times
				try
					set windowId to id of w
					set activeId to id of active tab of w
					set tabIds to id of tabs of w
					set tabUrls to URL of tabs of w
					set tabTitles to title of tabs of w
				on error m number n
					if my isGoneError(n) then exit repeat
					error m number n
				end try
				set c to count of tabIds
				if c is (count of tabUrls) and c is (count of tabTitles) then
					repeat with i from 1 to c
						set tabId to item i of tabIds
						set end of tabRecords to {windowId, tabId, tabId is activeId, item i of tabUrls, item i of tabTitles}
					end repeat
					exit repeat
				end if
			end repeat
		end tell
	end repeat
	set tabLines to {}
	set savedDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to character id 31
	repeat with r in tabRecords
		set end of tabLines to (contents of r) as text
	end repeat
	set AppleScript's text item delimiters to character id 30
	set out to tabLines as text
	set AppleScript's text item delimiters to savedDelimiters
	return out
end listTabs
