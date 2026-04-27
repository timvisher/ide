on currentBrowser()
	set browserName to "Vivaldi"
	try
		set browserName to paragraph 1 of (read POSIX file ((POSIX path of (path to home folder)) & ".config/timvisher/ide/AppleScript/Script Libraries/timvisher Browser.config/default_browser"))
	end try
	return browserName
end currentBrowser

on activate()
	tell application (my currentBrowser()) to activate
end activate

on getActiveTabUrl()
	tell script (my currentBrowser()) to getActiveTabUrl()
end getActiveTabUrl

on getActiveTabYtDlpUrl()
	tell script (my currentBrowser()) to getActiveTabYtDlpUrl()
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
