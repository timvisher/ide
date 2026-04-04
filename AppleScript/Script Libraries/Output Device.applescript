on setOutputDevice(outputDeviceName)
	if getOutputDevice() as text is equal to outputDeviceName then
		display notification "Output device already '" & outputDeviceName & "'"
	else
		try
			tell script "timvisher utilities" to doShellScript({"/opt/homebrew/bin/SwitchAudioSource", "-s", quoted form of outputDeviceName})
			display notification "Set output device to '" & outputDeviceName & "'"
		on error
			display notification "'" & outputDeviceName & "' does not exist"
		end try
	end if
end setOutputDevice

-- setOutputDevice(getHeadphoneDeviceName())

-- setOutputDevice(getSpeakerDeviceName())

-- setOutputDevice("External Headphones")

on getOutputDevice()
	tell script "timvisher utilities" to doShellScript({"/opt/homebrew/bin/SwitchAudioSource", "-c"})
end getOutputDevice

on getSpeakerDeviceName()
	tell script "timvisher utilities"
		set deviceList to doShellScript({"/opt/homebrew/bin/SwitchAudioSource", "-a"})
	end tell
	repeat with p in paragraphs of deviceList
		if p starts with "MacBook " and p ends with " Speakers" then
			return p as text
		end if
	end repeat
	error "No speakers found. Impossible."
end getSpeakerDeviceName

-- getSpeakerDeviceName()

on getHeadphoneDeviceName()
	tell script "timvisher utilities"
		set deviceList to doShellScript({"/opt/homebrew/bin/SwitchAudioSource", "-a"})
	end tell
	repeat with p in paragraphs of deviceList
		log p
		if p as text is equal to "Jabra EVOLVE LINK" or p as text is equal to "External Headphones" then
			return p as text
		end if
	end repeat
	return missing value
end getHeadphoneDeviceName

-- getHeadphoneDeviceName()

on toggleOutputDevice()
	set selectedDeviceName to getOutputDevice()
	set speakerDeviceName to getSpeakerDeviceName()
	
	if "Jabra EVOLVE LINK" is equal to selectedDeviceName or "External Headphones" is equal to selectedDeviceName then
		setOutputDevice(getSpeakerDeviceName())
		
		(*
		if application "Spotify" is running then
			tell application "Spotify"
				set sound volume to 47
			end tell
		end if
*)
		
		if application "VLC" is running then
			tell application "VLC"
				if muted then
					mute
				end if
				set audio volume to 160
			end tell
		end if
		
		set volume output volume 80
	else if selectedDeviceName starts with "MacBook " and selectedDeviceName ends with " Speakers" then
		setOutputDevice(getHeadphoneDeviceName())
		
		(*
		if application "Spotify" is running then
			tell application "Spotify"
				set sound volume to 47
			end tell
		end if
*)
		
		if application "VLC" is running then
			tell application "VLC"
				if muted then
					mute
				end if
				set audio volume to 160
			end tell
		end if
		
		set volume output volume 80
	end if
end toggleOutputDevice

-- toggleOutputDevice()
