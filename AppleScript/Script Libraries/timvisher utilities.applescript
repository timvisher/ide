on runHomeScript(homeFolderPosixPath)
	run script (POSIX path of (path to home folder) & homeFolderPosixPath)
end runHomeScript

on doShellScript(commandList)
	(*
	  You may be tempted to fancy quote handling to doShellScript.
	  Don't do it. AppleScript's quoting facilities are not powerful enough
	  to express the general case that would actually be useful. Just do
	  the quoting yourself.
	 *)
	set textCommandList to {}
	repeat with i in commandList
		set end of textCommandList to i as text
	end repeat
	set text item delimiters to space
	set command to textCommandList as text
	set text item delimiters to ""
	
	do shell script command
end doShellScript

-- doShellScript({POSIX path of (path to home folder) & "bin/chrome_new_profile_window", "user@example.com"})

-- doShellScript({"/opt/homebrew/bin/SwitchAudioSource", "-s", quoted form of "Jabra EVOLVE LINK"})
