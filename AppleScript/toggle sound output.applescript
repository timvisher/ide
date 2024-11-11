considering numeric strings
	if "14.0" is less than or equal to system version of (system info) then
		tell application "System Settings"
			reveal pane "Sound"
		end tell
		
		tell application "System Events"
			tell application process "System Settings"
				repeat 10 times
					if exists window "Sound" then
						exit repeat
					end if
					delay 0.1
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
					
					if "MacBook Air Speakers" is outputDeviceName then
						set speakersRow to n
					end if
				end repeat
				
				if selectedDeviceName is "Jabra EVOLVE LINK" then
					set selected of item speakersRow of rs to true
					display notification "Set output device to ‘MacBook Air Speakers’"
				else
					set selected of item jabraRow of rs to true
					display notification "Set output device to ‘Jabra EVOLVE LINK’"
				end if
			end tell
		end tell
	else if "13.0" is less than or equal to system version of (system info) then
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
				
				set rs to rows of table 1 of scroll area 1 of group 2 of scroll area 1 of group 1 of group 2 of splitter group 1 of group 1 of window "Sound"
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
					
					if "MacBook Air Speakers" is outputDeviceName then
						set speakersRow to n
					end if
				end repeat
				
				if selectedDeviceName is "Jabra EVOLVE LINK" then
					set selected of item speakersRow of rs to true
					display notification "Set output device to ‘MacBook Air Speakers’"
				else
					set selected of item jabraRow of rs to true
					display notification "Set output device to ‘Jabra EVOLVE LINK’"
				end if
			end tell
		end tell
	else
		-- See https://apple.stackexchange.com/questions/217148/using-apple-script-to-manage-sound-output-selection
		tell application "System Settings" to reveal anchor "output" of pane id "com.apple.preference.sound"
		
		tell application "System Events"
			tell application process "System Preferences"
				set t to (time of (current date) as number) + 5
				repeat until exists tab group 1 of window "Sound"
					if ((time of (current date)) as number) is greater than t then
						display dialog "Unable to activate Sound preferences pane"
						tell application "System Settings" to activate
						tell me to error "Unable to activate Sound preferences pane"
					end if
					delay 0.25
				end repeat
				
				tell tab group 1 of window "Sound"
					set DevicesCount to count rows of table 1 of scroll area 1
					repeat with n from 0 to DevicesCount
						if (selected of row n of table 1 of scroll area 1) then
							set SelectedDevice to n
							set selectedDeviceName to value of text field 1 of row n of table 1 of scroll area 1
						end if
						
						try
							if "Jabra EVOLVE LINK" is (value of text field 1 of row n of table 1 of scroll area 1) then
								set jabraRow to n
							end if
							
							if "MacBook Air Speakers" is (value of text field 1 of row n of table 1 of scroll area 1) then
								set speakersRow to n
							end if
						on error
							-- don't care
						end try
						
					end repeat
					
					if selectedDeviceName is "Jabra EVOLVE LINK" then
						set selected of row speakersRow of table 1 of scroll area 1 to true
						display notification "Set output device to ‘MacBook Air Speakers’"
					else
						set selected of row jabraRow of table 1 of scroll area 1 to true
						display notification "Set output device to ‘Jabra EVOLVE LINK’"
					end if
				end tell
			end tell
		end tell
	end if
end considering

tell application "System Settings" to quit