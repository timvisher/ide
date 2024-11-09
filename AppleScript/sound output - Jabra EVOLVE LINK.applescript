-- See https://apple.stackexchange.com/questions/217148/using-apple-script-to-manage-sound-output-selection
-- See https://gist.github.com/rmcdongit/f66ff91e0dad78d4d6346a75ded4b751?permalink_comment_id=4286384#gistcomment-4286384
do shell script "open 'x-apple.systempreferences:com.apple.Sound-Settings.extension'"

tell application "System Events"
	tell application process "System Settings"
		set t to (time of (current date) as number) + 5
		repeat until exists group 1 of window "Sound"
			if ((time of (current date)) as number) is greater than t then
				display dialog "Unable to activate Sound preferences pane"
				tell application "System Settings" to activate
				tell me to error "Unable to activate Sound preferences pane"
			end if
			delay 0.25
		end repeat
		
		set rs to rows of outline 1 of scroll area 1 of group 2 of scroll area 1 of group 1 of group 2 of splitter group 1 of group 1 of window "Sound"
		repeat with n from 1 to count of rs
			set r to item n of rs
			set outputDeviceName to value of static text 1 of group 1 of UI element 1 of r
			if selected of r then
				set selectedDeviceRowNumber to n
				set selectedDeviceName to outputDeviceName
			end if
			
			if "Jabra EVOLVE LINK" is outputDeviceName then
				set jabraRow to n
			end if
			
			if "MacBook Pro Speakers" is outputDeviceName then
				set speakersRow to n
			end if
		end repeat
		
		if selectedDeviceName is not "Jabra EVOLVE LINK" then
			set selected of item jabraRow of rs to true
			display notification "Set output device to ÔJabra EVOLVE LINKÕ"
		else
			display notification "Output device is ÔJabra EVOLVE LINKÕ"
		end if
	end tell
end tell

tell application "System Settings" to quit