tell application "Google Chrome"
	set playlistsToEnqueue to {}
	repeat with w in windows
		repeat with t in (tabs whose URL contains "//open.spotify.com/playlist/") of w
			-- https://open.spotify.com/playlist/2bFtHCJ3QR7B3odfjBR2xw
			set playlist to execute t javascript (read (open for access (POSIX path of (path to home folder)) & "/bin/chrome_js/music_title.js"))
			set playlistToEnqueue to {|url|:URL of t, |type|:"playlist", playlist:playlist, |tab|:t}
			set end of playlistsToEnqueue to playlistToEnqueue
		end repeat
	end repeat
	set y to ""
	repeat with playlistToEnqueue in playlistsToEnqueue
		set y to y & "- url: " & (|url| of playlistToEnqueue) & "
  type: " & (|type| of playlistToEnqueue) & "
  playlist: " & (playlist of playlistToEnqueue) & "
"
		log |url| of playlistToEnqueue
		log |type| of playlistToEnqueue
		log playlist of playlistToEnqueue
	end repeat
	
	set qf to (open for access (POSIX path of (path to home folder) & "/bin/evernote_current_music_url.queue.yaml") with write permission)
	write y to qf starting at eof
	close access qf
	repeat with playlistToEnqueue in playlistsToEnqueue
		tell |tab| of playlistToEnqueue to close
	end repeat
end tell