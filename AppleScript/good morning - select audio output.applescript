tell script "Output Device"
	set targetOutputDevice to getSpeakerDeviceName()
	set maybeHeadphoneDevice to getHeadphoneDeviceName()
	if maybeHeadphoneDevice is not missing value then
		set targetOutputDevice to maybeHeadphoneDevice
	end if
	
	setOutputDevice(targetOutputDevice)
end tell