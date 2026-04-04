on maybe_kill_distraction(appName)
	(*
	The structure of this is important. Applescript can directly check
	whether the app is running or not. Only System Events appears to be
	able to check whether it's visible though, and _only_ as an
	"application process". System Events, then, can't issue the quit
	command. Only Applescript directly can do that. Thus you have to
	Check if the app is running using Applescript, descend into System
	Events with a variable to check whether or not it's hidden, and
	then come back to Applescript to issue the quit if appropriate.
     *)
	try
		if application appName is running then
			set shouldQuit to false
			tell application "System Events"
				try
					if visible of application process appName is false then
						set shouldQuit to true
					end if
				on error
					display notification "Failed to decide if application is visible"
				end try
			end tell

			if shouldQuit then
				try
					tell application appName to quit
				on error
					display notification "Failed to quit " & appName
				end try
			end if
		end if
	on error
		display notification "Failed to determine if application is running " & appName
	end try
end maybe_kill_distraction

on idle
	set distractionApps to {}
	set end of distractionApps to "Slack"

	repeat with distractionApp in distractionApps
		maybe_kill_distraction(distractionApp)
	end repeat

	set distractionUrls to {}
	set end of distractionUrls to "mail.google.com"
	set end of distractionUrls to "example.com"
	set end of distractionUrls to "chrome://newtab/"

	set distractionUrlsAggressiveKill to {}
	set end of distractionUrlsAggressiveKill to "zoom.us/j/"
	set end of distractionUrlsAggressiveKill to "/user-consent/login-success.html"
	set end of distractionUrlsAggressiveKill to "http://127.0.0.1:29001/saml"
	set end of distractionUrlsAggressiveKill to "slack.com/ssb/signin_redirect"

	try
		set extraUrls to paragraphs of (read POSIX file ((POSIX path of (path to home folder)) & ".config/timvisher/ide/AppleScript/config/distraction-killer-extra-urls"))
		repeat with u in extraUrls
			if u is not "" then set end of distractionUrlsAggressiveKill to u
		end repeat
	end try

	if application "Google Chrome" is running then
		try
			tell application "Google Chrome"
				set toDestroy to {}
				repeat with distractionUrl in distractionUrls
					repeat with theTab in (tabs of windows whose URL contains distractionUrl)
						set doDestroy to true
						repeat with activeTab in active tab of windows
							if id of activeTab is id of theTab then
								set doDestroy to false
							end if
						end repeat

						if doDestroy then
							set toDestroy to (items of toDestroy) & {theTab}
						end if
					end repeat
				end repeat
				repeat with distractionUrlAggressiveKill in distractionUrlsAggressiveKill
					repeat with theTab in (tabs of windows whose URL contains distractionUrlAggressiveKill)
						set end of toDestroy to theTab
					end repeat
				end repeat
				repeat with theTab in toDestroy
					close theTab
				end repeat
				if (count of tabs of windows) is 0 then quit
			end tell
		on error
			display notification "Couldn't kill a tab"
		end try

	end if
	return 300
end idle
