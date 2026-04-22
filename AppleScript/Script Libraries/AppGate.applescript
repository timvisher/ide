property postQuitDelaySeconds : 3
property postWriteDelaySeconds : 1

on connectToProfile(profileId)
	quitIfRunning()
	delay postQuitDelaySeconds
	setProfile(profileId)
	delay postWriteDelaySeconds
	tell application "AppGate SDP" to activate
end connectToProfile

on quitIfRunning()
	if application "AppGate SDP" is not running then return
	tell application "AppGate SDP" to quit
	set tryUntil to (current date) + 10
	repeat while application "AppGate SDP" is running
		delay 0.5
		if tryUntil < (current date) then
			set m to "AppGate SDP failed to quit in 10 seconds. Giving up."
			display notification m
			error m
		end if
	end repeat
end quitIfRunning

on setProfile(profileId)
	do shell script "defaults write com.appgate.sdp.service profile -string " & quoted form of profileId
	do shell script "defaults write com.appgate.sdp.service autosaml -bool true"

	(*
	  Earlier version wrote the plist directly via System Events:

	  set plistPath to (POSIX path of (path to home folder)) & "Library/Preferences/com.appgate.sdp.service.plist"
	  tell application "System Events"
	    tell property list file plistPath
	      set value of property list item "profile" to profileId
	      set value of property list item "autosaml" to true
	    end tell
	  end tell

	  That form did land on disk — `defaults read com.appgate.sdp.service`
	  reflected the new values immediately after — but AppGate ignored
	  them on relaunch: the profile wouldn't switch and the UI's
	  "Browser/Certificate auto sign-in" toggle stayed green even with
	  autosaml=false. Routing through `defaults write` (i.e. cfprefsd)
	  fixed it, matching what nlopez's appgate-cli.sh does.
	 *)
end setProfile
