tell application "Google Chrome" to set the_url to execute active tab of front window javascript "
if (document.location.hostname.includes(\"youtube.com\")) {
  params = new URLSearchParams(document.location.search.substring(1));
  document.location.protocol + \"//\" + document.location.hostname + document.location.pathname + \"?v=\" + params.get(\"v\");
} else {
  document.location.href
}
"

tell script "timvisher Terminal" to runCommandInteractively("cd ~/Downloads/Evernote && yt-dlp --write-description --format b '" & the_url & "' && sleep 5 && exit")

