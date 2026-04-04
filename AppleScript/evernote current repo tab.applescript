tell script "Google Chrome" to set theUrl to getActiveTabUrl()

tell script "Alacritty" to runCommandInteractively("cd ~/Downloads/Evernote && git clone '" & theUrl & "' && sleep 5 && exit")
