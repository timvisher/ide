if (document.location.hostname.includes('youtube.com')) {
  params = new URLSearchParams(document.location.search.substring(1));

  if (null != params.get("v")) {
    console.log("v search param is present. Cleaning URL");
    new URL(document.location.protocol + "//" + document.location.hostname + document.location.pathname + "?v=" + params.get("v")).toString();
  } else {
    console.log("v search param is not present. Assuming URL should be used verbatim");
    document.location.href;
  }
} else {
  document.location.href;
}
