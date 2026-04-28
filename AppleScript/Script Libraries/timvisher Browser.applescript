on currentBrowser()
	set browserName to "Vivaldi"
	try
		set browserName to paragraph 1 of (read POSIX file ((POSIX path of (path to home folder)) & ".config/timvisher/ide/AppleScript/Script Libraries/timvisher Browser.config/default_browser"))
	end try
	return browserName
end currentBrowser

-- `activate` is also a verb in AppleScript's standard suite, so an
-- empty `()` arglist parses ambiguously. The `{}` empty-list form
-- forces handler-call interpretation. Don't "fix" this back to `()`.
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
	-- Trade-off: routing URL access through `execute javascript` lets us
	-- run canonicalization (Jira selectedIssue, Amazon /dp/) in-page, but
	-- Chrome blocks JS injection on chrome://, chrome-extension://, and
	-- chrome-error:// tabs -- so getActiveTabUrl() will fail on those. If
	-- you need URLs of internal pages, fall back to `get URL of active
	-- tab of front window` (no canonicalization, but works everywhere).
	--
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
	-- Pre-check existence so we can surface the install hint. AppleScript's
	-- generic file-not-found error doesn't tell the user that ~/bin probably
	-- needs to be re-symlinked, which is the most common cause for missing
	-- ~/bin/browser_js/*.js files in this project.
	tell application "System Events"
		if not (exists file fullPath) then
			set msg to homeFolderPosixPath & " missing at " & fullPath & " -- run `bash ~/git/ide/bash/install.bash` to relink ~/bin."
			display dialog msg
			error msg
		end if
	end tell
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
