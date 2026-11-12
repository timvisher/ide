import json
import subprocess
import time

from timvisher import logging
from timvisher.gh import store
from timvisher.gh.errors import USAGE, fail

REVIEW_THREADS = """query ReviewThreads($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        pageInfo { hasNextPage }
        nodes {
          id isResolved isOutdated path line startLine diffSide
          comments(first: 100) { pageInfo { hasNextPage } nodes { databaseId id url } }
        }
      }
    }
  }
}"""


THREAD_PAGE = """query ThreadPage($owner: String!, $repo: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id isResolved isOutdated path line startLine diffSide
          comments(first: 1) { nodes { databaseId id url } }
        }
      }
    }
  }
}"""


def thread_of_root(spec, owner, repo, number, database_id):
    after = []
    while True:
        found = api(spec, "graphql", "-f", f"query={THREAD_PAGE}", "-f", f"owner={owner}", "-f", f"repo={repo}",
                    "-F", f"number={number}", *after)
        connection = found["data"]["repository"]["pullRequest"]["reviewThreads"]
        for node in connection["nodes"]:
            if node["comments"]["nodes"] and node["comments"]["nodes"][0]["databaseId"] == database_id:
                return node
        page = connection.get("pageInfo") or {}
        if not page.get("hasNextPage"):
            return None
        after = ["-f", f"after={page['endCursor']}"]


class NotFound(Exception):
    pass


class Progress:
    def __init__(self, label, total, interval=3.0):
        self.label = label
        self.total = total
        self.interval = interval
        self.done = 0
        self.logged = time.monotonic()

    def step(self):
        self.done += 1
        now = time.monotonic()
        if self.done in (1, self.total) or self.interval <= now - self.logged:
            logging.info("%s: %d/%d", self.label, self.done, self.total)
            self.logged = now


# A payload without a reaction summary is looked up, not taken as unreacted.
def _reacted(comment):
    return (comment.get("reactions") or {}).get("total_count", 1) != 0


def _plural(count, noun):
    return f"{count} {noun}{'' if count == 1 else 's'}"


def api(repo, *args):
    done = subprocess.run(["gh", "-R", repo, "api", *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True)
    if done.returncode != 0:
        if "(HTTP 404)" in done.stderr:
            raise NotFound(args[-1])
        fail("timvisher_gh_gh_failed", f"'gh api {' '.join(args)}' failed for {repo}.", reason=done.stderr.strip(),
             suggestions=["Check gh's error, then retry"])
    return json.loads(done.stdout) if done.stdout.strip() else None


class Fetcher:
    def __init__(self, state, now):
        self.state = state
        self.now = now
        self._viewer = None
        self.taken = set()
        self.seen = set()
        self.partial = False

    def viewer(self, repo):
        if self._viewer is None:
            self._viewer = api(repo, "user")["login"]
        return self._viewer

    def _known(self, object_id):
        return self.state.db.execute("SELECT store_path FROM objects WHERE id = ?", (object_id,)).fetchone()

    def _put(self, *, id, kind, url, owner, repo, key, raw, remote, only_new, number=None, database_id=None,
             parent_id=None):
        db = self.state.db
        self.seen.add(id)
        known = self._known(id)
        if known and only_new:
            return False
        if known:
            key = known[0]
        else:
            key = store.unique(store.root(), key, self.taken)
            self.taken.add(key)
        store.register(db, id=id, kind=kind, url=url, owner=owner, repo=repo, number=number,
                       database_id=database_id, parent_id=parent_id, store_path=key)
        db.execute("UPDATE objects SET fetched_at = ? WHERE id = ?", (self.now, id))
        db.execute("INSERT INTO raw VALUES (?, ?, ?) ON CONFLICT (object_id) DO UPDATE SET "
                   "payload = excluded.payload, fetched_at = excluded.fetched_at", (id, json.dumps(raw), self.now))
        for name, value in remote.items():
            store.set_remote(db, id, name, value, self.now)
        self.state.touch(id)
        return True

    def _fresh(self, object_id, only_new):
        return not (only_new and self._known(object_id))

    def _reactions(self, spec, endpoint, comment, progress):
        if not _reacted(comment):
            return []
        progress.step()
        mine = [r["content"] for r in api(spec, "--paginate", endpoint) if r["user"]["login"] == self.viewer(spec)]
        return sorted(mine)

    def _lookups(self, label, total):
        if total:
            logging.info("Looking up reactions on %s: %s to make", label, _plural(total, "API call"))
        return Progress(f"Looking up reactions on {label}", total)

    def pr(self, owner, repo, number, *, conversation=True, only_new=False):
        spec = f"{owner}/{repo}"
        pull = api(spec, f"repos/{spec}/pulls/{number}")
        owner, repo = pull["html_url"].split("/")[3:5]
        spec = f"{owner}/{repo}"
        pr_key = store.pr_key(owner, repo, number)
        state = "merged" if pull.get("merged") else pull["state"]
        self._put(id=pull["node_id"], kind="pr", url=pull["html_url"], owner=owner, repo=repo, number=number,
                  database_id=pull.get("id"), key=pr_key, raw=pull, only_new=only_new,
                  remote={"title": pull["title"], "body": pull.get("body") or "", "draft": pull["draft"],
                          "base": pull["base"]["ref"], "state": state})
        pr_id = pull["node_id"]
        pr_key = self._known(pr_id)[0]
        if not conversation:
            return pr_id
        label = f"{spec}#{number}"
        logging.info("Listing %s's comments, review threads and reviews: 4 API calls", label)
        comments = api(spec, "--paginate", f"repos/{spec}/issues/{number}/comments")
        review_comments = {c["id"]: c for c in api(spec, "--paginate", f"repos/{spec}/pulls/{number}/comments")}
        threads = api(spec, "graphql", "-f", f"query={REVIEW_THREADS}", "-f", f"owner={owner}", "-f", f"repo={repo}",
                      "-F", f"number={number}")
        reviews = [review for review in api(spec, "--paginate", f"repos/{spec}/pulls/{number}/reviews")
                   if review["state"] != "PENDING"]
        connection = threads["data"]["repository"]["pullRequest"]["reviewThreads"]
        nodes = connection["nodes"]
        self.partial = (connection.get("pageInfo") or {}).get("hasNextPage", False) or any(
            (node["comments"].get("pageInfo") or {}).get("hasNextPage", False) for node in nodes)
        threaded = [(node, ids) for node in nodes
                    if (ids := [c["databaseId"] for c in node["comments"]["nodes"]
                                if c["databaseId"] in review_comments])]
        lookups = sum(self._fresh(c["node_id"], only_new) and _reacted(c) for c in comments)
        for node, ids in threaded:
            lookups += self._fresh(node["id"], only_new) and _reacted(review_comments[ids[0]])
            lookups += sum(self._fresh(review_comments[i]["node_id"], only_new) and _reacted(review_comments[i])
                           for i in ids[1:])
        logging.info("%s has %s, %s in %s and %s", label, _plural(len(comments), "comment"),
                     _plural(sum(len(ids) for _, ids in threaded), "review comment"),
                     _plural(len(threaded), "thread"), _plural(len(reviews), "review"))
        progress = self._lookups(label, lookups)
        self._comments(spec, owner, repo, comments, pr_id, pr_key, only_new, progress)
        for node, ids in threaded:
            root = review_comments[ids[0]]
            self.seen.add(node["id"])
            if self._fresh(node["id"], only_new):
                name = store.thread_name(root["created_at"], root["user"]["login"], root.get("path"), root.get("line"))
                reactions = self._reactions(spec, f"repos/{spec}/pulls/comments/{root['id']}/reactions", root,
                                            progress)
                self._put(id=node["id"], kind="thread", url=root["html_url"], owner=owner, repo=repo,
                          database_id=root["id"], parent_id=pr_id, key=store.child_key(pr_key, "threads", name),
                          raw={"root": root, "thread": node}, only_new=only_new,
                          remote={"body": root["body"], "resolved": node["isResolved"], "reactions": reactions})
            thread_key = self._known(node["id"])[0]
            for reply_id in ids[1:]:
                reply = review_comments[reply_id]
                self.seen.add(reply["node_id"])
                if not self._fresh(reply["node_id"], only_new):
                    continue
                name = store.comment_name(reply["created_at"], reply["user"]["login"], reply["body"])
                reactions = self._reactions(spec, f"repos/{spec}/pulls/comments/{reply['id']}/reactions", reply,
                                            progress)
                self._put(id=reply["node_id"], kind="comment", url=reply["html_url"], owner=owner, repo=repo,
                          database_id=reply["id"], parent_id=node["id"],
                          key=store.child_key(thread_key, "replies", name), raw=reply, only_new=only_new,
                          remote={"body": reply["body"], "reactions": reactions})
        for review in reviews:
            self.seen.add(review["node_id"])
            name = store.review_name(review["submitted_at"], review["user"]["login"])
            self._put(id=review["node_id"], kind="review", url=review["html_url"], owner=owner, repo=repo,
                      database_id=review["id"], parent_id=pr_id, key=store.child_key(pr_key, "reviews", name),
                      raw=review, only_new=only_new, remote={"body": review.get("body") or "", "state": review["state"]})
        if not only_new:
            self._archive_missing(pr_id)
        return pr_id

    # PRs and issues share the issue-comments endpoint for their top-level
    # comments.
    def _comments(self, spec, owner, repo, comments, parent_id, parent_key, only_new, progress):
        for comment in comments:
            self.seen.add(comment["node_id"])
            if not self._fresh(comment["node_id"], only_new):
                continue
            name = store.comment_name(comment["created_at"], comment["user"]["login"], comment["body"])
            reactions = self._reactions(spec, f"repos/{spec}/issues/comments/{comment['id']}/reactions", comment,
                                        progress)
            self._put(id=comment["node_id"], kind="comment", url=comment["html_url"], owner=owner, repo=repo,
                      database_id=comment["id"], parent_id=parent_id, key=store.child_key(parent_key, "comments", name),
                      raw=comment, only_new=only_new, remote={"body": comment["body"], "reactions": reactions})

    # Past GraphQL's first 100 threads or replies an object wasn't seen, not
    # deleted, so an incomplete page archives nothing.
    def _archive_missing(self, pr_id):
        if self.partial:
            return
        db = self.state.db
        query = ("SELECT id FROM objects WHERE deleted_at IS NULL AND store_path NOT LIKE 'archive/%' AND "
                 "(parent_id = ? OR parent_id IN (SELECT id FROM objects WHERE parent_id = ? AND kind = 'thread'))")
        for (child,) in db.execute(query, (pr_id, pr_id)).fetchall():
            row = db.execute("SELECT store_path FROM objects WHERE id = ?", (child,)).fetchone()
            if child not in self.seen and not row[0].startswith("archive/"):
                store.archive(db, child, self.now)
                self.state.touch(child)

    # GitHub's issues endpoint answers for PRs too; treating one as an issue
    # would archive its threads, replies and reviews as missing.
    def issue(self, owner, repo, number, *, conversation=False, only_new=False):
        spec = f"{owner}/{repo}"
        found = api(spec, f"repos/{spec}/issues/{number}")
        if found.get("pull_request") or "/pull/" in found["html_url"]:
            fail("timvisher_gh_issue_is_a_pr", f"{spec}#{number} is a PR, not an issue.",
                 status=USAGE, suggestions=[f"Use its PR URL, {found['html_url'].split('#')[0]}, "
                                            "with 'timvisher_gh pr' or 'timvisher_gh comment'"])
        owner, repo = found["html_url"].split("/")[3:5]
        number = found["number"]
        spec = f"{owner}/{repo}"
        self._put(id=found["node_id"], kind="issue", url=found["html_url"], owner=owner, repo=repo, number=number,
                  database_id=found.get("id"), key=store.issue_key(owner, repo, number), raw=found, only_new=only_new,
                  remote={"title": found["title"], "body": found.get("body") or "", "state": found["state"]})
        issue_id = found["node_id"]
        if not conversation:
            return issue_id
        label = f"{spec}#{number}"
        logging.info("Listing %s's comments: 1 API call", label)
        comments = api(spec, "--paginate", f"repos/{spec}/issues/{number}/comments")
        logging.info("%s has %s", label, _plural(len(comments), "comment"))
        progress = self._lookups(label, sum(self._fresh(c["node_id"], only_new) and _reacted(c) for c in comments))
        self._comments(spec, owner, repo, comments, issue_id, self._known(issue_id)[0], only_new, progress)
        if not only_new:
            self._archive_missing(issue_id)
        return issue_id
