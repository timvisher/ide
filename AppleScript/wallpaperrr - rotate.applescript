tell application "System Events"
	repeat with d in desktops
		tell application "Finder"
			--set sourceDirectoryAbsolutePath to POSIX path of (path to home folder as alias) & "Pictures/wallpaperrr/library/2560x1600/"
			set sourceDirectoryAbsolutePath to POSIX path of (path to home folder as alias) & "Pictures/OS 9 Wallpaper/"
			set sourceDirectory to POSIX file sourceDirectoryAbsolutePath as alias
			set nextWallpaperFile to some file of sourceDirectory
		end tell
		set picture rotation of desktops to 0
		set picture of d to POSIX path of disk item (nextWallpaperFile as string)
	end repeat
end tell
