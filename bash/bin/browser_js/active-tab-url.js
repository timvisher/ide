(function() {
  var l = window.location;
  var h = l.href;
  if (l.href.includes("atlassian.net/jira")) {
    // Jira: collapse selectedIssue query param to canonical /browse/<KEY>
    var maybeSelectedIssue = new URLSearchParams(l.search).get('selectedIssue');
    if (maybeSelectedIssue) {
      h = l.protocol + "//" + l.host + "/browse/" + maybeSelectedIssue;
    }
  } else if (l.hostname.includes("amazon.com")) {
    // Amazon: strip everything after the product id, keep the slug.
    h = l.origin + "/" + l.pathname.split("/").slice(1, 4).join("/") + "/";
  }
  return h;
})()
