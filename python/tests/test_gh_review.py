import json
import unittest

from support.case import GhTestCase
from support.remotes import git
from timvisher.gh import state

REPO = "testuser/testrepo"
PR = f"https://github.com/{REPO}/pull/7"


class ReviewTest(GhTestCase):
    def setUp(self):
        super().setUp()
        git("checkout", "-q", "-b", "feature", cwd=self.work)
        self.github.add_pull(REPO, 7, head="feature", title="T", author="bob")
        self.github.respond(["pr", "list"], stdout=json.dumps([{"number": 7, "state": "OPEN"}]))

    def review(self, *args, stdin=None):
        rc, out, err = self.run_gh("review", *args, TIMVISHER_AGENT="1", stdin=stdin)
        self.err = err
        return rc, out

    def codes(self):
        return [json.loads(line)["code"] for line in self.err.splitlines() if line.startswith('{"type":"instruction"')]

    def write(self, name, text):
        path = self.work / name
        path.write_text(text)
        return path

    def url(self, review_id):
        return f"{PR}#pullrequestreview-{review_id}"

    def reviews(self):
        return self.github.state["reviews"]

    def dismissals(self):
        return [c for c in self.github.calls if c.get("path", "").endswith("/dismissals")]

    def test_delete_prompts_for_your_pending_review(self):
        pending = self.github.add_review(REPO, 7, user="testuser", state="PENDING")
        self.assertEqual((0, ""), self.review("delete", self.url(pending), stdin="n\n"))
        self.assertIn(f"Delete the pending review {self.url(pending)} and its draft comments? [y/N] \n", self.err)
        self.assertEqual(["timvisher_gh_delete_skipped"], self.codes())
        self.assertIn(str(pending), self.reviews())
        self.assertEqual((0, ""), self.review("delete", self.url(pending), stdin="y\n"), self.err)
        self.assertEqual((["timvisher_gh_deleted"], {}), (self.codes(), self.reviews()))

    def test_delete_with_a_pr_target_or_none_finds_your_pending_review(self):
        self.github.add_review(REPO, 7, user="alice", state="PENDING")
        mine = self.github.add_review(REPO, 7, user="testuser", state="PENDING")
        self.assertEqual(0, self.review("delete", "--force")[0], self.err)
        self.assertNotIn(str(mine), self.reviews())
        self.assertEqual(1, len(self.reviews()))
        self.assertEqual((0, ""), self.review("delete", "--force", PR), self.err)
        self.assertEqual(["timvisher_gh_already_deleted"], self.codes())

    def test_delete_force_refuses_someone_elses_pending_review(self):
        theirs = self.github.add_review(REPO, 7, user="alice", state="PENDING")
        rc, _ = self.review("delete", "--force", self.url(theirs))
        self.assertEqual((2, ["timvisher_gh_delete_not_yours"]), (rc, self.codes()))
        self.assertIn(str(theirs), self.reviews())
        self.assertEqual(0, self.review("delete", self.url(theirs), stdin="y\n")[0], self.err)
        self.assertIn("by alice", self.err)
        self.assertEqual({}, self.reviews())

    def test_delete_refuses_a_submitted_review_and_suggests_dismissing_it(self):
        approved = self.github.add_review(REPO, 7, user="testuser", state="APPROVED")
        rc, _ = self.review("delete", "--force", self.url(approved))
        self.assertEqual((1, ["timvisher_gh_review_submitted"]), (rc, self.codes()))
        self.assertIn("review dismiss", self.err)
        self.assertEqual("APPROVED", self.reviews()[str(approved)]["state"])

    def test_delete_of_a_review_already_gone_and_plan(self):
        self.assertEqual((0, ""), self.review("delete", "--force", self.url(4242)), self.err)
        self.assertEqual(["timvisher_gh_already_deleted"], self.codes())
        pending = self.github.add_review(REPO, 7, user="testuser", state="PENDING")
        self.assertEqual((0, f"- review  {self.url(pending)}  delete\n"),
                         self.review("delete", "--plan", "--force", self.url(pending)))
        self.assertIn(str(pending), self.reviews())

    def test_dismiss_moves_the_message_into_the_store_and_converges_idempotently(self):
        approved = self.github.add_review(REPO, 7, user="alice", state="APPROVED")
        message = self.write("x.why.md", "Superseded by the rewrite\n")
        url = self.url(approved)
        self.assertEqual((0, f"{url}\n"), self.review("dismiss", url, str(message), stdin="y\n"), self.err)
        self.assertIn(f"Dismiss alice's APPROVED review {url}? It can't be undone. [y/N] ", self.err)
        self.assertEqual(["timvisher_gh_dismissed"], self.codes())
        found = self.reviews()[str(approved)]
        self.assertEqual(("DISMISSED", "Superseded by the rewrite"), (found["state"], found["dismissal_message"]))
        self.assertTrue(message.is_symlink())
        self.assertEqual(("reviews", "dismissal.md"), (message.resolve().parent.parent.name, message.resolve().name))
        self.assertEqual("DISMISSED\n", self.run_gh("review", "info", url, ".state")[1])
        mark = len(self.dismissals())
        self.assertEqual((0, f"{url}\n"), self.review("dismiss", url, str(message), "--force"), self.err)
        self.assertEqual((["timvisher_gh_already_dismissed"], mark), (self.codes(), len(self.dismissals())))
        self.assertEqual((0, f"{url}\n"), self.review("push", str(message)), self.err)
        self.assertEqual((["timvisher_gh_already_dismissed"], mark), (self.codes(), len(self.dismissals())))

    def test_dismiss_force_dismisses_yours_and_refuses_someone_elses(self):
        mine = self.github.add_review(REPO, 7, user="testuser", state="CHANGES_REQUESTED")
        self.assertEqual(0, self.review("dismiss", "--force", self.url(mine), str(self.write("m.md", "x\n")))[0],
                         self.err)
        self.assertEqual("DISMISSED", self.reviews()[str(mine)]["state"])
        theirs = self.github.add_review(REPO, 7, user="alice", state="APPROVED")
        message = self.write("t.md", "x\n")
        rc, _ = self.review("dismiss", "--force", self.url(theirs), str(message))
        self.assertEqual((2, ["timvisher_gh_dismiss_not_yours"]), (rc, self.codes()))
        self.assertEqual(("APPROVED", False), (self.reviews()[str(theirs)]["state"], message.is_symlink()))

    def test_dismiss_refuses_what_github_wont_dismiss_before_changing_anything(self):
        commented = self.github.add_review(REPO, 7, user="alice", state="COMMENTED")
        pending = self.github.add_review(REPO, 7, user="testuser", state="PENDING")
        approved = self.github.add_review(REPO, 7, user="alice", state="APPROVED")
        message = self.write("m.md", "x\n")
        for review_id, rc, code in ((commented, 1, "timvisher_gh_review_not_dismissable"),
                                    (pending, 1, "timvisher_gh_review_not_dismissable")):
            self.assertEqual(rc, self.review("dismiss", self.url(review_id), str(message), stdin="y\n")[0])
            self.assertEqual([code], self.codes())
        self.assertIn("review delete", self.err)
        self.assertEqual(2, self.review("dismiss", self.url(approved), str(self.write("e.md", "\n\n")),
                                        stdin="y\n")[0])
        self.assertEqual(2, self.review("dismiss", PR, str(message), stdin="y\n")[0])
        self.github.add_repo(REPO, push=False, admin=False)
        rc, _ = self.review("dismiss", self.url(approved), str(message), stdin="y\n")
        self.assertEqual((1, ["timvisher_gh_review_dismiss_no_write"]), (rc, self.codes()))
        self.assertNotIn("[y/N]", self.err)
        self.assertEqual(([], False), (self.dismissals(), message.is_symlink()))
        self.assertEqual("APPROVED", self.reviews()[str(approved)]["state"])

    def test_dismiss_plan_changes_nothing(self):
        approved = self.github.add_review(REPO, 7, user="alice", state="APPROVED")
        message = self.write("m.md", "x\n")
        rc, out = self.review("dismiss", "--plan", self.url(approved), str(message))
        self.assertEqual((0, f"~ review  {self.url(approved)}  dismiss alice's APPROVED review\n"), (rc, out),
                         self.err)
        self.assertEqual(([], False, "APPROVED"),
                         (self.dismissals(), message.is_symlink(), self.reviews()[str(approved)]["state"]))

    def test_push_applies_a_wanted_dismissal_that_didnt_land(self):
        approved = self.github.add_review(REPO, 7, user="alice", state="APPROVED")
        message = self.write("m.md", "Stale\n")
        url = self.url(approved)
        self.github._update(lambda s: s.update(fail_dismissals=True))
        self.assertEqual(1, self.review("dismiss", url, str(message), stdin="y\n")[0])
        self.assertTrue(message.is_symlink())
        self.assertEqual("APPROVED", self.reviews()[str(approved)]["state"])
        self.assertEqual("DISMISSED\n", self.run_gh("review", "info", url, '.posted["source.state"]')[1])
        self.github._update(lambda s: s.update(fail_dismissals=False))
        self.assertEqual((0, f"{url}\n"), self.review("push", url), self.err)
        self.assertEqual(["timvisher_gh_dismissed"], self.codes())
        self.assertEqual(("DISMISSED", "Stale"),
                         (self.reviews()[str(approved)]["state"], self.reviews()[str(approved)]["dismissal_message"]))

    def test_dismiss_retried_with_the_stored_message_keeps_it(self):
        approved = self.github.add_review(REPO, 7, user="alice", state="APPROVED")
        message = self.write("m.md", "Stale\n")
        url = self.url(approved)
        self.github._update(lambda s: s.update(fail_dismissals=True))
        self.assertEqual(1, self.review("dismiss", url, str(message), stdin="y\n")[0])
        stored = message.resolve()
        self.github._update(lambda s: s.update(fail_dismissals=False))
        self.assertEqual((0, f"{url}\n"), self.review("dismiss", url, str(stored), stdin="y\n"), self.err)
        self.assertEqual((False, "Stale\n", "Stale"), (stored.is_symlink(), stored.read_text(),
                                                       self.reviews()[str(approved)]["dismissal_message"]))

    def test_dismiss_with_a_relative_symlink_message_keeps_its_text(self):
        approved = self.github.add_review(REPO, 7, user="alice", state="APPROVED")
        (self.work / "notes").mkdir()
        real = self.write("notes/why.md", "Superseded\n")
        message = self.work / "why.md"
        message.symlink_to("notes/why.md")
        url = self.url(approved)
        self.assertEqual((0, f"{url}\n"), self.review("dismiss", url, str(message), stdin="y\n"), self.err)
        self.assertEqual(("Superseded", "dismissal.md", "Superseded\n", "Superseded\n"),
                         (self.reviews()[str(approved)]["dismissal_message"], message.resolve().name,
                          message.read_text(), real.read_text()))

    def test_push_without_a_wanted_state_does_nothing(self):
        approved = self.github.add_review(REPO, 7, user="alice", state="APPROVED")
        self.assertEqual((0, ""), self.review("push", self.url(approved)), self.err)
        self.assertEqual((["timvisher_gh_nothing_to_do"], []), (self.codes(), self.dismissals()))

    def test_a_review_url_is_still_its_pr_for_other_nouns(self):
        approved = self.github.add_review(REPO, 7, user="alice", state="APPROVED")
        self.assertEqual("7\n", self.run_gh("pr", "info", self.url(approved), ".number")[1])
        self.assertEqual("alice\n", self.run_gh("review", "info", self.url(approved), ".author")[1])

    def test_info_finds_your_pending_review_and_a_pr_pull_keeps_it(self):
        pending = self.github.add_review(REPO, 7, user="testuser", state="PENDING")
        url = self.url(pending)
        self.assertEqual("PENDING\n", self.run_gh("review", "info", url, ".state")[1])
        self.assertEqual(0, self.run_gh("pr", "pull", PR)[0])
        self.assertEqual("null\n", self.run_gh("review", "info", url, ".deleted_at")[1])
        self.assertEqual(0, self.review("delete", "--force", url)[0], self.err)
        self.assertNotEqual("null\n", self.run_gh("review", "info", url, ".deleted_at")[1])

    def test_rerunning_delete_leaves_the_archived_copy_where_it_is(self):
        pending = self.github.add_review(REPO, 7, user="testuser", state="PENDING")
        url = self.url(pending)
        self.assertEqual(0, self.run_gh("review", "info", url)[0])
        self.assertEqual(0, self.review("delete", "--force", url)[0], self.err)
        self.assertEqual((0, ""), self.review("delete", "--force", url), self.err)
        self.assertEqual(["timvisher_gh_already_deleted"], self.codes())
        self.assertEqual([], [p for p in state.root().rglob("*") if "archive/archive" in str(p)])
        self.assertTrue(list(state.root().rglob("archive/**/review.json")))

    def test_help_documents_every_verb(self):
        rc, out = self.review("--help")
        self.assertEqual(0, rc)
        for words in ("delete", "dismiss", "push", "info", "dismissal.md", "--force"):
            self.assertIn(words, out)
        self.assertEqual(2, self.review("bogus")[0])
        rc, out, _ = self.run_gh("review", "info", "--help")
        self.assertEqual(0, rc)
        self.assertIn("submitted_at", out)


if __name__ == "__main__":
    unittest.main()
