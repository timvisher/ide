tell application "System Events"
	-- This doesn't work for some Google Chrome contexts (like a small pop up window that doesn't look like a window visually). Consider trying to use tabs to get at the underlying window in that case
	tell (first application process whose frontmost is true)
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

return

tell application "iTerm"
	set currentBounds to bounds of front window
	
	set width to item 3 of currentBounds
	
	copy currentBounds to tempBounds
	
	set item 3 of tempBounds to (width - (width * 0.1))
	
	set bounds of front window to tempBounds
	
	delay 0.25
	
	set bounds of front window to currentBounds
end tell
