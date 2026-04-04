run script POSIX path of (path to home folder) & "git/ide/AppleScript/vlc safe restart.applescript"

tell application "VLC"
	OpenURL "http://somafm.com/groovesalad.pls"
end tell

tell application "System Events" to set visible of last application process whose name is "VLC" to false
