on mute()
	
	(*
	if application "Spotify" is running then
		tell application "Spotify" to set sound volume to 0
	end if
*)
	
	if application "VLC" is running then
		tell application "VLC"
			if not muted then
				mute
			end if
		end tell
	end if
end mute

on isMuted()
	set spotifyMuted to false
	
	(*
	if application "Spotify" is running then
		tell application "Spotify"
			set spotifyMuted to 0 is equal to sound volume
		end tell
	end if
*)
	
	set vlcMuted to false
	if application "VLC" is running then
		tell application "VLC"
			set vlcMuted to muted
		end tell
	end if
	
	return spotifyMuted or vlcMuted
end isMuted

on volumeUp()
	
	(*
	if application "Spotify" is running then
		tell application "Spotify"
			set sound volume to 47
		end tell
	end if
*)
	
	if application "VLC" is running then
		tell application "VLC"
			if muted then
				mute
			end if
			set audio volume to 160
		end tell
	end if
	
	set targetOutputVolume to 80 -- Everything but External Headphones
	
	tell script "Output Device"
		if getOutputDevice() as text is equal to "External Headphones" then
			set targetOutputVolume to 60 -- Pink Ear Buds
		end if
	end tell
	
	set volume output volume targetOutputVolume
end volumeUp

on volumeDown()
	
	(*
	if application "Spotify" is running then
		tell application "Spotify"
			set sound volume to 10
		end tell
	end if
*)
	
	if application "VLC" is running then
		tell application "VLC"
			set audio volume to 50
		end tell
	end if
	
	set targetOutputVolume to 100 -- Everything but External Headphones
	tell script "Output Device"
		if getOutputDevice() as text is equal to "External Headphones" then
			set targetOutputVolume to 80 -- Pink Ear Buds
		end if
	end tell
	
	set volume output volume targetOutputVolume
end volumeDown

on getCurrentBackgroundNoise()
	
	(*
	if application "VLC" is running and application "Spotify" is running then
		tell application "VLC" to set vlcPlaying to playing
		tell application "Spotify" to set spotifyPlaying to player state is playing
		if vlcPlaying and spotifyPlaying then
			set m to "Spotify and VLC are both playing. Impossible"
			display notification m
			error m
		end if
	end if
*)
	if application "VLC" is running then
		tell application "VLC"
			if playing then
				return "VLC: " & path of current item as text
			end if
		end tell
	end if
	
	(*
	if application "Spotify" is running then
		tell application "Spotify"
			if player state is playing then
				return "Spotify: " & name of current track & " by " & artist of current track
			end if
		end tell
	end if
*)
	return missing value
end getCurrentBackgroundNoise

-- getCurrentBackgroundNoise()

(*
on spotifyEnsurePaused()
	if application "Spotify" is running then
		tell application "Spotify" to pause
	end if
end spotifyEnsurePaused
*)

on hideBackgroundNoiseApps()
	
	(*
	if application "Spotify" is running then
		tell application "System Events" to set visible of application process "Spotify" to false
	end if
*)
	
	tell application "System Events"
		if 1 is less than (count of (application processes whose name is "VLC")) then
			set visible of (last application process whose name is "VLC") to false
		end if
	end tell
end hideBackgroundNoiseApps

-- hideBackgroundNoiseApps()

on vlcPlayUrl(theUrl)
	--spotifyEnsurePaused()
	tell application "VLC" to OpenURL theUrl
	volumeUp()
	hideBackgroundNoiseApps()
end vlcPlayUrl

on vlcEnsurePaused()
	if application "VLC" is running then
		tell application "VLC"
			if playing then
				play
			end if
		end tell
	end if
end vlcEnsurePaused


(*
on playSpotifyTrack(theTrack)
	vlcEnsurePaused()
	tell application "Spotify"
		with timeout of 5 seconds
			play track theTrack
		end timeout
		set visibleAndPlayingCount to 0
		set tryUntil to (current date) + 10
		repeat until 5 is less than or equal to visibleAndPlayingCount
			if tryUntil is less than (current date) then
				display notification "Inconceivable! Couldn't play Spotify in time. Giving up." with title "background noise"
				exit repeat
			end if
			tell application "System Events"
				set isVisible to visible of application process "Spotify"
			end tell
			tell application "Spotify"
				set isPlaying to player state is playing
			end tell
			if isVisible and isPlaying then
				set visibleAndPlayingCount to visibleAndPlayingCount + 1
			end if
			if not isVisible or not isPlaying then
				set visibleAndPlayingCount to 0
			end if
			delay 0.1
		end repeat
	end tell
	volumeUp()
	hideBackgroundNoiseApps()
end playSpotifyTrack
*)

on playUrl(theUrl)
	vlcPlayUrl(theUrl)
end playUrl

-- playUrl("https://musicforprogramming.net/rss.xml")

-- playSpotifyTrack("spotify:playlist:37i9dQZF1DX9sIqqvKsjG8") -- Instrumental Study