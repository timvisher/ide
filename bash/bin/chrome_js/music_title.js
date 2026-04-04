switch (document.location.host) {
  // case "music.youtube.com":
  //   document.querySelector('h1 .title').innerText;
  //   break;
  // case "youtube.com":
  // case "www.youtube.com":
  //   document.querySelector('h1[aria-label]').innerText;
  //   break;
case "open.spotify.com":
  (
    // https://open.spotify.com/artist/3RNrq3jvMZxD9ZyoOZbQOD
    document.querySelector("[data-encore-id='adaptiveTitle']") ||
      // devtools://devtools/bundled/devtools_app.html?remoteBase=https://chrome-devtools-frontend.appspot.com/serve_file/@6872a1daec36b43916ec4b91c7cb3899762cf853/&targetType=tab&can_dock=true
    document.querySelector('h1')
  ).innerText;
  break;
default:
  console.log(`music_title.js: Unsupported host ‘${document.location.host}’`)
}
