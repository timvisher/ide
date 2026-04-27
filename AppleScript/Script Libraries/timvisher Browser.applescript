property currentBrowser : "Vivaldi"

on activate()
	tell application (currentBrowser of script "timvisher Browser") to activate
end activate

on getActiveTabUrl()
	tell script (currentBrowser of script "timvisher Browser") to getActiveTabUrl()
end getActiveTabUrl

on getActiveTabYtDlpUrl()
	tell script (currentBrowser of script "timvisher Browser") to getActiveTabYtDlpUrl()
end getActiveTabYtDlpUrl

on makeNewProfileWindow(profileIdentifier)
	tell script (currentBrowser of script "timvisher Browser") to makeNewProfileWindow(profileIdentifier)
end makeNewProfileWindow

on makeNewProfile2 given profileIdentifier:profileIdentifier : "", URL:urlArg : ""
	tell script (currentBrowser of script "timvisher Browser") to makeNewProfile2 given profileIdentifier:profileIdentifier, URL:urlArg
end makeNewProfile2

--makeNewProfileWindow("")

on getTabWithUrl(u)
	tell script (currentBrowser of script "timvisher Browser") to getTabWithUrl(u)
end getTabWithUrl

-- getTabWithUrl("https://www.youtube.com/@PogoMusic")
