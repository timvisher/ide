on currentBrowser()
	set browserName to "Vivaldi"
	try
		set browserName to paragraph 1 of (read POSIX file ((POSIX path of (path to home folder)) & ".config/timvisher/ide/AppleScript/Script Libraries/timvisher Browser.config/default_browser"))
	end try
	return browserName
end currentBrowser

on activate {}
	tell application (my currentBrowser()) to activate
end activate

on openUrl(u)
	tell application (my currentBrowser())
		activate
		open location u
	end tell
end openUrl

on executeJsInActiveTab(js)
	set b to my currentBrowser()
	if application b is not running then
		set msg to b & " is not running. No active tab to query."
		display dialog msg
		error msg
	end if
	-- `execute ... javascript ...` is Chrome/Chromium-specific terminology.
	-- `using terms from` lets the compiler resolve it while the runtime
	-- target stays dynamic (Chrome, Vivaldi, etc. share this dictionary).
	using terms from application "Google Chrome"
		tell application b
			execute active tab of front window javascript js
		end tell
	end using terms from
end executeJsInActiveTab

on executeJsFileInActiveTab(jsFile)
	executeJsInActiveTab((read jsFile))
end executeJsFileInActiveTab

on executeHomePOSIXJsFileInActiveTab(homeFolderPosixPath)
	set fullPath to (POSIX path of (path to home folder)) & homeFolderPosixPath
	executeJsFileInActiveTab(POSIX file fullPath)
end executeHomePOSIXJsFileInActiveTab

on getActiveTabUrl()
	executeHomePOSIXJsFileInActiveTab("bin/browser_js/active-tab-url.js")
end getActiveTabUrl

on getActiveTabYtDlpUrl()
	executeHomePOSIXJsFileInActiveTab("bin/browser_js/yt-dlp-url.js")
end getActiveTabYtDlpUrl

on makeNewProfileWindow(profileIdentifier)
	tell script (my currentBrowser()) to makeNewProfileWindow(profileIdentifier)
end makeNewProfileWindow

on makeNewProfile2 given profileIdentifier:profileIdentifier : "", URL:urlArg : ""
	tell script (my currentBrowser()) to makeNewProfile2 given profileIdentifier:profileIdentifier, URL:urlArg
end makeNewProfile2

--makeNewProfileWindow("")

on getTabWithUrl(u)
	tell script (my currentBrowser()) to getTabWithUrl(u)
end getTabWithUrl

-- getTabWithUrl("https://www.youtube.com/@PogoMusic")
