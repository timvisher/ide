evernote_current_music_url() {
  local artist_url

  while [[ -n $1 ]]
  do
    case $1 in
      --artist-url=*)
        artist_url=${1#--artist-url=}
        ;;
      *)
        error 'Unsupported option: ‘%s’' "$1"
        return 1
    esac

    shift
  done

  if [[ -z "$artist_url" ]]
  then
    artist_url=$(chrome_js_in_active_tab ~/bin/chrome_js/music_url.js)
  fi

  if [[ $artist_url != *?(open.spotify.com|youtube.com)* ]] || [[ $artist_url == *music.youtube.com* ]]
  then
    error 'Unsupported URL ‘%s’' "$artist_url"
    return 1
  fi

  if (( 0 == $# ))
  then
    history -s evernote_current_music_url
  fi
  history -s "$(printf '%q ' evernote_current_music_url --artist-url="${artist_url}")"

  command evernote_current_music_url --artist-url="${artist_url}"
}
