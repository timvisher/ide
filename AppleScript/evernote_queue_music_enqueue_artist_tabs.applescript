tell application "Google Chrome"
	set artistsToEnqueue to {}
	repeat with w in windows
		repeat with t in (tabs whose URL contains "//open.spotify.com/artist/") of w
			-- https://open.spotify.com/artist/3RNrq3jvMZxD9ZyoOZbQOD
			set artist to execute t javascript (read (open for access (POSIX path of (path to home folder)) & "/bin/chrome_js/music_title.js"))
			set artistToEnqueue to {|url|:URL of t, |type|:"artist", artist:artist, |tab|:t}
			set end of artistsToEnqueue to artistToEnqueue
		end repeat
	end repeat
	set y to ""
	repeat with artistToEnqueue in artistsToEnqueue
		set y to y & "- url: " & (|url| of artistToEnqueue) & "
  type: " & (|type| of artistToEnqueue) & "
  artist: " & (artist of artistToEnqueue) & "
"
		log |url| of artistToEnqueue
		log |type| of artistToEnqueue
		log artist of artistToEnqueue
	end repeat
	set qf to (open for access (POSIX path of (path to home folder) & "/bin/evernote_current_music_url.queue.yaml") with write permission)
	write y to qf starting at eof
	close access qf
	repeat with artistToEnqueue in artistsToEnqueue
		tell |tab| of artistToEnqueue to close
	end repeat
end tell