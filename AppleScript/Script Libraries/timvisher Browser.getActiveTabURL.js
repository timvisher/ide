console.log("welcome to `timvisher Browser.getActiveTabURL.js`")

l = window.location
h = l.href
if (l.href.includes("atlassian.net/jira")) {
  // Special handling of jira selected issues
  maybeSelectedIssue = new URLSearchParams(window.location.search).get('selectedIssue')
  if (maybeSelectedIssue) {
    h = l.protocol + "//" + l.host + "/browse/" + maybeSelectedIssue
  }
} else if (l.hostname.includes("amazon.com")) {
  // Special handling of amazon.com links to strip out the cruft after the
  // product id. Leaves the URL slug for link previewers.
  h = l.origin + "/" + l.pathname.split("/").slice(1, 4).join("/") + "/"
}
h
