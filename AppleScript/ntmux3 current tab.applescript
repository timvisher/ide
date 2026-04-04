tell script "Google Chrome" to set theUrl to getActiveTabUrl()

if (theUrl does not start with "https://github.com/" and theUrl does not contain "/pull/") then
	set errorMessage to "Ô" & theUrl & "Õ doesn't look like a PR"
	display dialog errorMessage
	error errorMessage
end if

tell script "timvisher Terminal" to runCommandInteractively("ntmux3")