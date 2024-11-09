tell application "System Events"
	tell application process "Alacritty"
	    -- /ht https://kaspars.net/blog/applescript-resize-all-windows
		set mySize to (get size of front window)
		set width to item 1 of mySize
		set height to item 2 of mySize
		set tempWidth to width * 0.9 as integer
		set tempSize to {tempWidth, height}
		set size of front window to tempSize
		delay 0.5
		set size of front window to mySize
	end tell
end tell