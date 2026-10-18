import json
import os
import unittest

from support.case import GhTestCase
from support.remotes import commit_on_remote, git

REPO = "testuser/testrepo"


class FakeGhTest(GhTestCase):
    def api(self, *args, stdin=None):
        rc, out, err = self.gh("api", *args, stdin=stdin)
        return rc, (json.loads(out) if out.strip() and out.lstrip()[:1] in "[{" else out), err

    def graphql(self, query, **variables):
        fields = [arg for name, value in variables.items() for arg in ("-F", f"{name}={value}")]
        return self.api("graphql", "-f", f"query={query}", *fields)

    def test_calls_are_recorded_with_repo_and_hostname(self):
        self.gh("-R", REPO, "api", "--hostname", "github.com", "user")
        call = self.github.calls[-1]
        self.assertEqual((REPO, "github.com", "GET", "user"),
                         (call["repo"], call["hostname"], call["method"], call["path"]))
        self.assertEqual(["-R", REPO, "api", "--hostname", "github.com", "user"], call["argv"])

    def test_repo_and_viewer(self):
        self.assertEqual("testuser", self.api("user", "--jq", ".login")[1].strip())
        self.assertEqual(("main", REPO), (lambda r: (r["default_branch"], r["full_name"]))(self.api(f"repos/{REPO}")[1]))
        rc, _, err = self.api("repos/nobody/nothing")
        self.assertEqual(1, rc)
        self.assertIn("Not Found (HTTP 404)", err)

    def test_pull_requests_are_created_listed_and_edited(self):
        _, created, _ = self.api(f"repos/{REPO}/pulls", "-f", "title=T", "-f", "body=B",
                                 "-f", "head=testuser:feature", "-F", "draft=true")
        self.assertEqual((1, "main", True, "https://github.com/testuser/testrepo/pull/1"),
                         (created["number"], created["base"]["ref"], created["draft"], created["html_url"]))
        _, listed, _ = self.api(f"repos/{REPO}/pulls?head=testuser:feature&state=all")
        self.assertEqual([1], [p["number"] for p in listed])
        self.api(f"repos/{REPO}/pulls/1", "-X", "PATCH", "-f", "title=T2", "-f", "base=dev")
        self.assertEqual(("T2", "dev"), (lambda p: (p["title"], p["base"]))(self.github.state["pulls"][REPO]["1"]))

    def test_issues_are_created_and_edited(self):
        _, created, _ = self.api(f"repos/{REPO}/issues", "-f", "title=T", "-f", "body=B")
        self.api(f"repos/{REPO}/issues/{created['number']}", "-X", "PATCH", "-f", "body=B2")
        self.assertEqual("B2", self.api(f"repos/{REPO}/issues/{created['number']}")[1]["body"])

    def test_issue_comments_are_created_edited_and_deleted(self):
        self.github.add_pull(REPO, 7, head="feature")
        _, comment, _ = self.api(f"repos/{REPO}/issues/7/comments", "-f", "body=hello")
        self.assertEqual("https://github.com/testuser/testrepo/pull/7#issuecomment-1001", comment["html_url"])
        self.api(f"repos/{REPO}/issues/comments/{comment['id']}", "-X", "PATCH", "-f", "body=edited")
        _, listed, _ = self.api(f"repos/{REPO}/issues/7/comments")
        self.assertEqual(["edited"], [c["body"] for c in listed])
        rc, out, _ = self.gh("api", "-i", "-X", "DELETE", f"repos/{REPO}/issues/comments/{comment['id']}")
        self.assertEqual((0, "HTTP/2.0 204 No Content"), (rc, out.splitlines()[0]))
        self.assertEqual([f"issue_comment:{comment['id']}"], self.github.state["deleted"])
        self.assertEqual(1, self.api(f"repos/{REPO}/issues/comments/{comment['id']}")[0])

    def test_review_comments_form_threads_and_replies_go_to_the_root(self):
        self.github.add_pull(REPO, 7, head="feature")
        _, root, _ = self.api(f"repos/{REPO}/pulls/7/comments", "-f", "body=nit", "-f", "path=a.go",
                              "-F", "line=4", "-f", "side=RIGHT", "-f", "commit_id=abc")
        _, reply, _ = self.api(f"repos/{REPO}/pulls/7/comments/{root['id']}/replies", "-f", "body=ok")
        _, nested, _ = self.api(f"repos/{REPO}/pulls/7/comments", "-f", "body=again", "-F", f"in_reply_to={reply['id']}")
        self.assertEqual((root["id"], root["id"]), (reply["in_reply_to_id"], nested["in_reply_to_id"]))
        thread = self.github.state["threads"][self.github.thread_of(root["id"])]
        self.assertEqual([root["id"], reply["id"], nested["id"]], thread["comments"])
        self.assertEqual(("a.go", 4), (root["path"], root["line"]))

    def test_reactions_are_added_once_listed_summarized_and_deleted(self):
        self.github.add_pull(REPO, 7, head="feature")
        comment_id = self.github.add_issue_comment(REPO, 7, "hi", user="alice")
        self.github.add_reaction("issue_comment", comment_id, "heart", user="alice")
        endpoint = f"repos/{REPO}/issues/comments/{comment_id}/reactions"
        _, mine, _ = self.api(endpoint, "-f", "content=+1")
        _, again, _ = self.api(endpoint, "-f", "content=+1")
        self.assertEqual(mine["id"], again["id"])
        _, listed, _ = self.api(endpoint)
        self.assertEqual({("heart", "alice"), ("+1", "testuser")}, {(r["content"], r["user"]["login"]) for r in listed})
        summary = self.api(f"repos/{REPO}/issues/comments/{comment_id}")[1]["reactions"]
        self.assertEqual((2, 1, 1), (summary["total_count"], summary["heart"], summary["+1"]))
        self.assertEqual(0, self.api("-X", "DELETE", f"{endpoint}/{mine['id']}")[0])
        self.assertEqual(["heart"], [r["content"] for r in self.api(endpoint)[1]])

    def test_review_comment_reactions(self):
        self.github.add_pull(REPO, 7, head="feature")
        root = self.github.add_review_comment(REPO, 7, "nit")
        self.api(f"repos/{REPO}/pulls/comments/{root}/reactions", "-f", "content=eyes")
        self.assertEqual(1, self.api(f"repos/{REPO}/pulls/comments/{root}")[1]["reactions"]["eyes"])

    def test_graphql_threads_resolution_and_viewer(self):
        self.github.add_pull(REPO, 7, head="feature")
        root = self.github.add_review_comment(REPO, 7, "nit", user="alice")
        self.github.add_review_comment(REPO, 7, "reply", reply_to=root)
        _, threads, _ = self.graphql("query ReviewThreads($owner: String!) { ... }", owner="testuser",
                                     repo="testrepo", number=7)
        node = threads["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"][0]
        self.assertEqual((False, 2), (node["isResolved"], len(node["comments"]["nodes"])))
        self.graphql("mutation ResolveReviewThread($threadId: ID!) { ... }", threadId=node["id"])
        self.assertTrue(self.github.state["threads"][node["id"]]["resolved"])
        self.graphql("mutation UnresolveReviewThread($threadId: ID!) { ... }", threadId=node["id"])
        self.assertFalse(self.github.state["threads"][node["id"]]["resolved"])
        self.assertEqual("testuser", self.graphql("query Viewer { viewer { login } }")[1]["data"]["viewer"]["login"])

    def test_graphql_draft_toggles(self):
        self.github.add_pull(REPO, 7, head="feature", draft=True)
        node_id = self.api(f"repos/{REPO}/pulls/7")[1]["node_id"]
        self.graphql("mutation MarkPullRequestReadyForReview($id: ID!) { ... }", id=node_id)
        self.assertFalse(self.github.state["pulls"][REPO]["7"]["draft"])
        self.graphql("mutation ConvertPullRequestToDraft($id: ID!) { ... }", id=node_id)
        self.assertTrue(self.github.state["pulls"][REPO]["7"]["draft"])

    def test_graphql_without_a_handler_fails_loudly(self):
        rc, _, err = self.graphql("query SomethingNew { x }")
        self.assertEqual(1, rc)
        self.assertIn("no GraphQL handler for SomethingNew", err)

    def test_input_and_typed_fields(self):
        self.github.add_pull(REPO, 7, head="feature")
        rc, comment, _ = self.api(f"repos/{REPO}/issues/7/comments", "--input", "-", stdin='{"body": "from stdin"}')
        self.assertEqual((0, "from stdin"), (rc, comment["body"]))
        self.graphql("query Viewer { viewer { login } }", n=3, flag="false")
        self.gh("api", "graphql", "-f", "query=query Viewer { viewer { login } }", "-f", "s=3")
        typed, raw = self.github.calls[-2]["fields"], self.github.calls[-1]["fields"]
        self.assertEqual((3, False, "3"), (typed["n"], typed["flag"], raw["s"]))

    def test_a_failed_request_leaves_state_unchanged(self):
        before = self.github.state
        self.api(f"repos/{REPO}/issues/99/comments", "-f", "body=nowhere")
        self.assertEqual(before, self.github.state)

    def test_canned_responses_serve_other_commands(self):
        self.github.respond(["pr", "checks"], stdout="[]\n")
        self.assertEqual((0, "[]\n"), self.gh("pr", "checks", "7", "--json", "state")[:2])
        rc, _, err = self.gh("pr", "merge", "7")
        self.assertEqual(1, rc)
        self.assertIn("unhandled command: gh pr merge 7", err)


class FixtureTest(GhTestCase):
    def test_the_worktree_resolves_to_its_github_repo(self):
        rc, out, _ = self.run_gh("info", ".me")
        self.assertEqual((0, "testuser\n"), (rc, out))
        self.assertEqual(REPO, self.github.calls[-1]["repo"])

    def test_pushes_and_fetches_go_to_the_bare_remote(self):
        git("commit", "-q", "--allow-empty", "-m", "mine", cwd=self.work)
        git("push", "-q", "origin", "HEAD", cwd=self.work)
        self.assertEqual(git("rev-parse", "HEAD", cwd=self.work), git("rev-parse", "main", cwd=self.remote))
        theirs = commit_on_remote(self.tmp, self.remote, "main", "theirs")
        git("fetch", "-q", "origin", cwd=self.work)
        self.assertEqual(theirs, git("rev-parse", "origin/main", cwd=self.work))

    def test_each_test_gets_a_fresh_xdg_data_home_under_its_own_home(self):
        self.assertTrue(os.environ["XDG_DATA_HOME"].startswith(f"{self.home}/"))
        other = GhTestCase("setUp")
        other.setUp()
        try:
            self.assertNotEqual(self.home, other.home)
        finally:
            other.doCleanups()

if __name__ == "__main__":
    unittest.main()
