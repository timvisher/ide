import json
import unittest

from support.case import GhTestCase
from support.remotes import git

REPO = "testuser/testrepo"
PR = f"https://github.com/{REPO}/pull/7"
ISSUE = f"https://github.com/{REPO}/issues/3"
LOOKUPS = f"Looking up reactions on {REPO}#7"


class FetchProgressTest(GhTestCase):
    def setUp(self):
        super().setUp()
        git("checkout", "-q", "-b", "feature", cwd=self.work)
        self.github.add_pull(REPO, 7, head="feature", title="T")
        self.github.respond(["pr", "list"], stdout=json.dumps([{"number": 7, "state": "OPEN"}]))

    def fetch(self, noun, url):
        rc, _, err = self.run_gh_as_tim(noun, "fetch", url, timvisher_logging_log_level="INFO")
        self.assertEqual(0, rc, err)
        return [line.split(": ", 1)[1] for line in err.splitlines() if " INFO " in line]

    def reaction_calls(self):
        return [c["path"] for c in self.github.calls if c.get("path", "").endswith("/reactions")]

    def info(self, url):
        return json.loads(self.run_gh("comment", "info", url, ".reactions | tojson")[1])

    def test_a_pr_fetch_projects_its_reaction_lookups_and_counts_them_off(self):
        plain = self.github.add_issue_comment(REPO, 7, "plan output")
        liked = self.github.add_issue_comment(REPO, 7, "nice")
        self.github.add_issue_comment(REPO, 7, "more plan output")
        root = self.github.add_review_comment(REPO, 7, "why?", user="carol")
        reply = self.github.add_review_comment(REPO, 7, "because", reply_to=root)
        self.github.add_review(REPO, 7, user="carol")
        self.github.add_reaction("issue_comment", liked, "heart", user="testuser")
        self.github.add_reaction("review_comment", reply, "rocket", user="carol")

        self.assertEqual([f"Listing {REPO}#7's comments, review threads and reviews: 4 API calls",
                          f"{REPO}#7 has 3 comments, 2 review comments in 1 thread and 1 review",
                          f"{LOOKUPS}: 2 API calls to make",
                          f"{LOOKUPS}: 1/2",
                          f"{LOOKUPS}: 2/2"], self.fetch("pr", PR))
        self.assertEqual([f"repos/{REPO}/issues/comments/{liked}/reactions",
                          f"repos/{REPO}/pulls/comments/{reply}/reactions"], self.reaction_calls())
        self.assertEqual((["heart"], [], []), (self.info(f"{PR}#issuecomment-{liked}"),
                                               self.info(f"{PR}#issuecomment-{plain}"),
                                               self.info(f"{PR}#discussion_r{reply}")))

    def test_a_conversation_nobody_reacted_to_makes_no_lookups(self):
        for body in ("one", "two"):
            self.github.add_issue_comment(REPO, 7, body)
        self.assertEqual([f"Listing {REPO}#7's comments, review threads and reviews: 4 API calls",
                          f"{REPO}#7 has 2 comments, 0 review comments in 0 threads and 0 reviews"],
                         self.fetch("pr", PR))
        self.assertEqual([], self.reaction_calls())

    def test_an_issue_fetch_projects_its_reaction_lookups(self):
        self.github.add_issue(REPO, 3, title="Bug")
        liked = self.github.add_issue_comment(REPO, 3, "same here")
        self.github.add_issue_comment(REPO, 3, "+1")
        self.github.add_reaction("issue_comment", liked, "+1", user="testuser")
        self.assertEqual([f"Listing {REPO}#3's comments: 1 API call",
                          f"{REPO}#3 has 2 comments",
                          f"Looking up reactions on {REPO}#3: 1 API call to make",
                          f"Looking up reactions on {REPO}#3: 1/1"], self.fetch("issue", ISSUE))
        self.assertEqual(["+1"], self.info(f"{ISSUE}#issuecomment-{liked}"))


if __name__ == "__main__":
    unittest.main()
