(function() {
  if (document.location.hostname.endsWith('youtube.com')) {
    var params = new URLSearchParams(document.location.search.substring(1));
    var v = params.get("v");
    if (v) {
      return new URL(document.location.protocol + "//" + document.location.hostname + document.location.pathname + "?v=" + v).toString();
    }
  }
  return document.location.href;
})()
