if application "Spotify" is running then
	tell application "Spotify"
		if player state is playing then
			display notification "background noise may already be playing"
			return
		end if
	end tell
end if

if application "VLC" is running then
	tell application "VLC"
		if playing then
			display notification "background noise may already be playing"
			return
		end if
	end tell
end if

tell script "Output Device"
	set currentOutputDevice to getOutputDevice() as text
	if currentOutputDevice is not equal to "Jabra EVOLVE LINK" and currentOutputDevice is not equal to "External Headphones" then
		display notification "Headphones not connected. Not playing background noise."
		return
	end if
end tell

set backgroundNoiseChoices to {}

set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:7GpEJ2SamJiBIknoi3gtwW", "Spotify Playlist: Ghostly: Productivity"}
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:6d3y6dkO8u8SdijPD7Vqr1", "Spotify Playlist: Ghostly: Ambient"}
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:37i9dQZF1DZ06evO0KP33w", "Spotify Playlist: This is Pogo"}
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:3vXUEGi4ip1EhI9OtdgdCy", "Spotify Playlist: Chilled Cow - ChilledCow - Lofi Girl - lofi hip hop music - beats to relax/study to…"}
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:7ByqzQtENcKQvyVjRjlM2z", "Spotify Playlist: Lofi Hip-Hop ✨ Chill Beats"}
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:0vvXsWCC9xrXsKd4FyS8kM", "Spotify Playlist: Lofi Girl - beats to relax/study to"}
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:37i9dQZF1DZ06evO0Poxt6", "Spotify Playlist: This is Explosions In The Sky"}
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:37i9dQZF1DZ06evO1Mom2c", "Spotify Playlist: This is Mogwai"}
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:37i9dQZF1DWXe9gFZP0gtP", "Spotify Playlist: Stress Relief"}
set end of backgroundNoiseChoices to {"spotify", "spotify:album:5iXHMwhLzhDSs7e0WK4svQ", "Spotify Album: Ambient 23 - Moby"}
set end of backgroundNoiseChoices to {"spotify", "spotify:album:063f8Ej8rLVTz9KkjQKEMa", "Spotify Album: Ambient 1: Music for Airports - Brian Eno"}
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:37i9dQZF1DX0jgyAiPl8Af", "Spotify Playlist: Peaceful Guitar"}
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:37i9dQZF1DX4sWSpwq3LiO", "Spotify Playlist: Peaceful Piano"}
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:37i9dQZF1DWXLeA8Omikj7", "Spotify Playlist: Brain Food"}
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:37i9dQZF1DWZeKCadgRdKQ", "Spotify Playlist: Deep Focus"}
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:37i9dQZF1DX9sIqqvKsjG8", "Spotify Playlist: Instrumental Study"}
-- set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:37i9dQZF1DWTLSN7iG21yC", "Spotify Playlist: Work From Home"} -- Lyrics
set end of backgroundNoiseChoices to {"applescript", "git/ide/AppleScript/background noise - dronezone.applescript", "Applescript - SomaFM Dronezone"}
set end of backgroundNoiseChoices to {"applescript", "git/ide/AppleScript/background noise - groovesalad.applescript", "Applescript - SomaFM Groovesalad"}
set end of backgroundNoiseChoices to {"url", "https://musicforprogramming.net/rss.xml", "URL - Music for Programming RSS"}
-- set end of backgroundNoiseChoices to {"url", "https://soundcloud.com/tycho/sanctuary-burning-man-sunrise-23", "URL - Tycho's Burning Man Sunrise Set - 2023"} -- Broken as of 2024-11-15T15:07:30+0000
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:37i9dQZF1DZ06evO2qlHMh", "Spotify Playlist: This Is Balam Acab"} -- /ht Matt Bilyeu
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:37i9dQZF1DX6QClArDhvcW", "Spotify Playlist: Mellow Lofi Morning"}
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:37i9dQZF1DXaf6XmhwlgC6", "Spotify Playlist: Atmospheric Focus"}
-- https://open.spotify.com/track/4vlLgpTCEXNO2SrmIQnAWU?si=9d01cf97c4974cc0 via Ayaz Badouraly (Runtime Incident Review)
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6", "Spotify Playlist: Intense Studying"}
set end of backgroundNoiseChoices to {"spotify", "spotify:playlist:5W7rf2Ufw17JATXk1sug3F", "Spotify Playlist: Cozy video game music ✨🍁 relaxing, cute and chill vibes"}


log backgroundNoiseChoices

set backgroundNoiseChoice to some item of backgroundNoiseChoices

display notification "Playing " & item 3 of backgroundNoiseChoice
log backgroundNoiseChoice

tell script "Background Noise"
	if item 1 of backgroundNoiseChoice is "spotify" then
		playSpotifyTrack(item 2 of backgroundNoiseChoice)
	else if item 1 of backgroundNoiseChoice is "applescript" then
		tell script "timvisher utilities" to runHomeScript(item 2 of backgroundNoiseChoice)
	else if item 1 of backgroundNoiseChoice is "url" then
		playUrl(item 2 of backgroundNoiseChoice)
	else
		msg = "Bad entry in backgroundNoiseChoices" & backgroundNoiseChoice
		display dialog msg
		error msg
	end if
end tell
