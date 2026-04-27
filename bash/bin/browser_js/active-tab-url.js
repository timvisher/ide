(function() {
  const l = window.location;
  let h = l.href;
  if (l.hostname.endsWith("atlassian.net") && l.pathname.startsWith("/jira")) {
    // Jira: collapse selectedIssue query param to canonical /browse/<KEY>
    const maybeSelectedIssue = new URLSearchParams(l.search).get('selectedIssue');
    if (maybeSelectedIssue) {
      h = l.protocol + "//" + l.host + "/browse/" + maybeSelectedIssue;
    }
  } else if (
    (l.hostname === "amazon.com" || l.hostname.endsWith(".amazon.com")) &&
    // Only canonicalize product pages (/dp/<id>, /gp/product/<id>). Search,
    // deals, root, etc. are left alone — slicing them to 3 segments would
    // strip query strings or yield amazon.com//.
    /^\/(dp|gp\/product)\//.test(l.pathname)
  ) {
    h = l.origin + "/" + l.pathname.split("/").slice(1, 4).join("/") + "/";
  }
  return h;
})()
