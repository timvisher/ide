if (document.location.hostname.includes('youtube.com')) {
  params = new URLSearchParams(document.location.search.substring(1));

  new URL(document.location.protocol + "//" + document.location.hostname + document.location.pathname + "?v=" + params.get("v")).toString();
} else {
  document.location.href
}
