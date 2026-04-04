tell application "System Events" to set username to name of current user
tell application "Finder"
	activate
	open home
	eject (disks whose ejectable is true)
	eject (disks whose local volume is false and owner is username)
end tell
