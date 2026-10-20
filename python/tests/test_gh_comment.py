import json
import unittest

from support.case import GhTestCase
from support.remotes import git
from timvisher.gh import state

REPO = "testuser/testrepo"
PR = f"https://github.com/{REPO}/pull/7"


class CommentTest(GhTestCase):
    def setUp(self):
        super().setUp()
        git("checkout", "-q", "-b", "feature", cwd=self.work)
        self.github.add_pull(REPO, 7, head="feature", title="T")
        self.github.respond(["pr", "list"], stdout=json.dumps([{"number": 7, "state": "OPEN"}]))

    def comment(self, *args, stdin=None):
        rc, out, err = self.run_gh("comment", *args, TIMVISHER_AGENT="1", stdin=stdin)
        self.err = err
        return rc, out

    def codes(self):
        return [json.loads(line)["code"] for line in self.err.splitlines() if line.startswith('{"type":"instruction"')]

    def write(self, name, text):
        path = self.work / name
        path.write_text(text)
        return path

    def posts(self):
        return [c for c in self.github.calls if c.get("method") in ("POST", "PATCH", "DELETE")]

    def issue_comments(self):
        return {int(k): v for k, v in self.github.state["issue_comments"].items()}

    def test_a_pr_target_posts_a_top_level_comment_and_promotes_the_file(self):
        source = self.write("note.md", "Looks good\n")
        rc, out = self.comment(PR, str(source))
        self.assertEqual(0, rc, self.err)
        [(comment_id, posted)] = self.issue_comments().items()
        self.assertEqual((f"{PR}#issuecomment-{comment_id}\n", "Looks good"), (out, posted["body"]))
        self.assertTrue(source.is_symlink())
        self.assertIn("/comments/", str(source.resolve()))

    def test_no_target_means_the_worktrees_pr(self):
        source = self.write("note.md", "Hi\n")
        self.assertEqual(0, self.comment(str(source))[0], self.err)
        self.assertEqual(["Hi"], [c["body"] for c in self.issue_comments().values()])

    def test_rerunning_a_posted_file_posts_nothing_again(self):
        source = self.write("note.md", "Once\n")
        self.comment(PR, str(source))
        mark = len(self.github.calls)
        rc, out = self.comment(PR, str(source))
        self.assertEqual(0, rc, self.err)
        self.assertEqual([], [c for c in self.github.calls[mark:] if c.get("method") == "POST"])
        self.assertEqual(1, len(self.issue_comments()))

    def test_a_tracked_file_syncs_its_body(self):
        source = self.write("note.md", "First\n")
        self.comment(PR, str(source))
        source.write_text("Second\n")
        self.assertEqual(0, self.comment(str(source))[0], self.err)
        self.assertEqual(["Second"], [c["body"] for c in self.issue_comments().values()])

    def test_a_review_comment_target_replies_in_its_thread_and_a_reply_target_replies_at_the_root(self):
        root = self.github.add_review_comment(REPO, 7, "nit", user="bob")
        first = self.github.add_review_comment(REPO, 7, "first reply", reply_to=root, user="bob")
        source = self.write("reply.md", "fixed\n")
        rc, out = self.comment("reply", f"{PR}#discussion_r{first}", str(source))
        self.assertEqual(0, rc, self.err)
        new = max(int(k) for k in self.github.state["review_comments"])
        self.assertEqual((root, f"{PR}#discussion_r{new}\n"),
                         (self.github.state["review_comments"][str(new)]["in_reply_to_id"], out))
        self.assertIn("/replies/", str(source.resolve()))

    def test_a_top_level_comment_target_is_an_error(self):
        top = self.github.add_issue_comment(REPO, 7, "top", user="bob")
        rc, _ = self.comment(f"{PR}#issuecomment-{top}", str(self.write("x.md", "x\n")))
        self.assertEqual(2, rc)
        self.assertEqual([], self.posts())

    def test_reply_needs_a_review_comment_or_thread(self):
        rc, _ = self.comment("reply", PR, str(self.write("x.md", "x\n")))
        self.assertEqual(2, rc)
        self.assertEqual([], self.posts())

    def test_a_file_posted_in_one_thread_isnt_posted_in_another(self):
        one = self.github.add_review_comment(REPO, 7, "one", user="bob")
        two = self.github.add_review_comment(REPO, 7, "two", path="b.go", user="bob")
        source = self.write("reply.md", "fixed\n")
        self.comment("reply", f"{PR}#discussion_r{one}", str(source))
        mark = len(self.github.calls)
        rc, _ = self.comment("reply", f"{PR}#discussion_r{two}", str(source))
        self.assertEqual(2, rc)
        self.assertEqual([], [c for c in self.github.calls[mark:] if c.get("method") == "POST"])

    def test_reaction_piggybacks_on_the_target_comment(self):
        root = self.github.add_review_comment(REPO, 7, "nit", user="bob")
        rc, _ = self.comment("reply", f"{PR}#discussion_r{root}", str(self.write("r.md", "done\n")),
                             "--reaction", "👍", "--reaction=rocket")
        self.assertEqual(0, rc, self.err)
        mine = self.github.state["reactions"][f"review_comment:{root}"]
        self.assertEqual({"+1", "rocket"}, {r["content"] for r in mine})

    def test_an_unknown_reaction_is_rejected_before_any_api_call(self):
        root = self.github.add_review_comment(REPO, 7, "nit", user="bob")
        mark = len(self.github.calls)
        rc, _ = self.comment("reply", f"{PR}#discussion_r{root}", str(self.write("r.md", "x\n")), "--reaction", "👍🏽")
        self.assertEqual((2, []), (rc, self.github.calls[mark:]))

    def test_reaction_with_a_pr_target_is_a_usage_error(self):
        self.assertEqual(2, self.comment(PR, str(self.write("x.md", "x\n")), "--reaction", "+1")[0])

    def test_edit_updates_under_the_lease(self):
        source = self.write("note.md", "One\n")
        self.comment(PR, str(source))
        [comment_id] = self.issue_comments()
        self.github._update(lambda s: s["issue_comments"][str(comment_id)].update(body="Changed on GitHub"))
        source.write_text("Mine\n")
        self.assertEqual(3, self.comment("edit", str(source))[0])
        self.assertIn("timvisher_gh_sync_conflict", self.codes())
        self.assertEqual(0, self.comment("edit", str(source), "--ours")[0], self.err)
        self.assertEqual("Mine", self.issue_comments()[comment_id]["body"])
        mark = len(self.github.calls)
        self.assertEqual(0, self.comment("edit", str(source))[0])
        self.assertEqual([], [c for c in self.github.calls[mark:] if c.get("method") == "PATCH"])

    def test_edit_errors_when_the_file_isnt_posted(self):
        rc, _ = self.comment("edit", str(self.write("x.md", "x\n")))
        self.assertEqual((1, ["timvisher_gh_comment_missing"]), (rc, self.codes()))

    def test_edit_by_url_pushes_the_store_copy(self):
        source = self.write("note.md", "One\n")
        self.comment(PR, str(source))
        [comment_id] = self.issue_comments()
        source.write_text("Two\n")
        self.assertEqual(0, self.comment("edit", f"{PR}#issuecomment-{comment_id}")[0], self.err)
        self.assertEqual("Two", self.issue_comments()[comment_id]["body"])

    def test_someone_elses_comment_is_never_pushed(self):
        theirs = self.github.add_issue_comment(REPO, 7, "theirs", user="alice")
        self.run_gh("pr", "pull")
        path = next(p for p in state.root().rglob("comment.md") if p.read_text() == "theirs\n")
        path.write_text("my edit\n")
        rc, _ = self.comment("push", str(path))
        self.assertEqual(0, rc, self.err)
        self.assertEqual("theirs", self.issue_comments()[theirs]["body"])
        self.assertIn("timvisher_gh_read_only", self.codes())

    def test_legacy_url_and_sidecar_files_are_adopted_without_posting(self):
        top = self.github.add_issue_comment(REPO, 7, "legacy")
        source = self.write("old.md", "legacy\n")
        self.write("old.md.url", f"{PR}#issuecomment-{top}\n")
        rc, _ = self.comment(str(source))
        self.assertEqual(0, rc, self.err)
        self.assertEqual([], self.posts())
        self.assertTrue(source.is_symlink())

    def test_react_adds_and_deletes_with_every_name_form(self):
        top = self.github.add_issue_comment(REPO, 7, "top", user="bob")
        url = f"{PR}#issuecomment-{top}"
        self.assertEqual(0, self.comment("react", url, "+1", "THUMBS_DOWN", "😄", "confused", "❤️", "HOORAY",
                                         "🚀", "eyes")[0], self.err)
        self.assertEqual({"+1", "-1", "laugh", "confused", "heart", "hooray", "rocket", "eyes"},
                         {r["content"] for r in self.github.state["reactions"][f"issue_comment:{top}"]})
        self.assertEqual(0, self.comment("react", "--delete", url, "heart")[0], self.err)
        self.assertNotIn("heart", {r["content"] for r in self.github.state["reactions"][f"issue_comment:{top}"]})

    def test_react_skips_reactions_already_made_and_deletions_never_made(self):
        top = self.github.add_issue_comment(REPO, 7, "top", user="bob")
        self.github.add_reaction("issue_comment", top, "eyes", user="testuser")
        self.github.add_reaction("issue_comment", top, "heart", user="bob")
        url = f"{PR}#issuecomment-{top}"
        mark = len(self.github.calls)
        self.assertEqual(0, self.comment("react", url, "eyes")[0])
        self.assertEqual(0, self.comment("react", "--delete", url, "heart")[0])
        self.assertEqual([], [c for c in self.github.calls[mark:] if c.get("method") in ("POST", "DELETE")])

    def test_react_rejects_a_skin_tone_before_any_api_call(self):
        top = self.github.add_issue_comment(REPO, 7, "top", user="bob")
        mark = len(self.github.calls)
        self.assertEqual((2, []), (self.comment("react", f"{PR}#issuecomment-{top}", "👍🏽")[0],
                                   self.github.calls[mark:]))

    def test_react_on_a_tracked_file_records_the_reactions(self):
        source = self.write("note.md", "Mine\n")
        self.comment(PR, str(source))
        self.assertEqual(0, self.comment("react", str(source), "rocket")[0], self.err)
        rc, out, _ = self.run_gh("comment", "info", str(source), ".reactions")
        self.assertEqual(["rocket"], json.loads(out))

    def test_delete_prompts_and_follows_the_answer(self):
        source = self.write("note.md", "Bye\n")
        self.comment(PR, str(source))
        [comment_id] = self.issue_comments()
        url = f"{PR}#issuecomment-{comment_id}"
        self.assertEqual((0, ""), self.comment("delete", url, stdin="n\n"))
        self.assertIn("[y/N] \n{", self.err)
        self.assertIn(comment_id, self.issue_comments())
        self.assertEqual((0, ""), self.comment("delete", url, stdin="y\n"))
        self.assertNotIn(comment_id, self.issue_comments())
        self.assertIn("/archive/", str(source.resolve()))
        self.assertEqual("Bye\n", source.read_text())

    def test_a_posted_file_aimed_at_another_pr_is_refused(self):
        self.github.add_pull(REPO, 8, head="other", title="O")
        source = self.write("note.md", "Hi\n")
        self.assertEqual(0, self.comment(PR, str(source))[0], self.err)
        source.write_text("Hi again\n")
        rc, _ = self.comment(f"https://github.com/{REPO}/pull/8", str(source))
        self.assertEqual(2, rc, self.err)
        self.assertEqual(["Hi"], [c["body"] for c in self.github.state["issue_comments"].values()])
        self.assertEqual(0, self.comment(PR, str(source))[0], self.err)
        self.assertEqual(["Hi again"], [c["body"] for c in self.github.state["issue_comments"].values()])

    def test_delete_of_a_comment_already_gone_archives_our_copy(self):
        source = self.write("note.md", "Bye\n")
        self.comment(PR, str(source))
        [comment_id] = self.issue_comments()
        self.github._update(lambda s: s["issue_comments"].pop(str(comment_id)))
        self.assertEqual((0, ""), self.comment("delete", "--force", str(source)), self.err)
        self.assertIn("timvisher_gh_already_deleted", self.codes())
        self.assertIn("/archive/", str(source.resolve()))

    def test_delete_force_deletes_yours_and_refuses_someone_elses(self):
        mine = self.github.add_issue_comment(REPO, 7, "mine")
        theirs = self.github.add_issue_comment(REPO, 7, "theirs", user="alice")
        self.assertEqual(0, self.comment("delete", "--force", f"{PR}#issuecomment-{mine}")[0], self.err)
        rc, _ = self.comment("delete", f"{PR}#issuecomment-{theirs}", "--force")
        self.assertEqual((2, ["timvisher_gh_delete_not_yours"]), (rc, self.codes()))
        self.assertEqual([theirs], list(self.issue_comments()))
        self.assertEqual(0, self.comment("delete", f"{PR}#issuecomment-{theirs}", stdin="y\n")[0])
        self.assertEqual({}, self.issue_comments())

    def test_delete_of_a_review_comment(self):
        root = self.github.add_review_comment(REPO, 7, "nit")
        self.assertEqual(0, self.comment("delete", "--force", f"{PR}#discussion_r{root}")[0], self.err)
        self.assertEqual({}, self.github.state["review_comments"])

    def test_every_comment_call_names_the_repo_with_r(self):
        root = self.github.add_review_comment(REPO, 7, "nit", user="bob")
        self.comment("reply", f"{PR}#discussion_r{root}", str(self.write("r.md", "x\n")), "--reaction", "eyes")
        self.assertTrue(self.github.calls)
        self.assertEqual({REPO}, {c["repo"] for c in self.github.calls})

    def test_fetch_and_pull_of_an_unposted_file_do_nothing(self):
        source = self.write("x.md", "x\n")
        for verb in ("fetch", "pull"):
            self.assertEqual((0, ""), self.comment(verb, str(source)), verb)
        self.assertEqual([], self.posts())

    def test_a_new_comment_is_recorded_from_the_post_itself(self):
        source = self.write("note.md", "Recorded\n")
        self.comment(PR, str(source))
        post = max(i for i, c in enumerate(self.github.calls) if c.get("method") == "POST")
        self.assertEqual([], [c for c in self.github.calls[post + 1:] if c.get("path", "").endswith("/comments")])
        self.assertTrue(source.is_symlink())

    def test_plan_neither_deletes_nor_reacts(self):
        top = self.github.add_issue_comment(REPO, 7, "top")
        url = f"{PR}#issuecomment-{top}"
        for args in (("delete", "--plan", "--force", url), ("react", "--plan", url, "eyes")):
            rc, out = self.comment(*args)
            self.assertEqual(0, rc, self.err)
            self.assertIn(url, out)
        self.assertEqual([], self.posts())
        self.assertIn(top, self.issue_comments())

    def test_open_opens_the_comment(self):
        log = self.tmp / "browser.log"
        fake = self.github.bin / "timvisher_browser"
        fake.write_text("#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> \"$FAKE_BROWSER_LOG\"\n")
        fake.chmod(0o755)
        rc, out, err = self.run_gh("comment", PR, str(self.write("o.md", "x\n")), "--open", TIMVISHER_AGENT="1",
                                   FAKE_BROWSER_LOG=str(log))
        self.assertEqual(0, rc, err)
        self.assertEqual(f"tab {out.strip()}\n", log.read_text())

    def test_fetch_and_pull_take_a_comment_url_alone_but_not_a_pr_url(self):
        top = self.github.add_issue_comment(REPO, 7, "top", user="bob")
        url = f"{PR}#issuecomment-{top}"
        self.assertEqual((0, f"{url}\n"), self.comment("fetch", url), self.err)
        self.assertEqual(0, self.comment("pull", url)[0], self.err)
        self.assertEqual(["top\n"], [p.read_text() for p in state.root().rglob("comment.md")])
        self.assertEqual(2, self.comment("fetch", PR)[0])

    def test_adopting_a_legacy_review_comment_root(self):
        root = self.github.add_review_comment(REPO, 7, "nit")
        source = self.write("nit.md", "nit\n")
        self.write("nit.md.url", f"{PR}#discussion_r{root}\n")
        rc, out = self.comment(str(source))
        self.assertEqual((0, f"{PR}#discussion_r{root}\n"), (rc, out), self.err)
        rc, out, _ = self.run_gh("thread", "info", f"{PR}#discussion_r{root}", ".root")
        self.assertEqual(f"{PR}#discussion_r{root}\n", out)

    def test_help_documents_every_verb(self):
        rc, out = self.comment("--help")
        self.assertEqual(0, rc)
        for verb in ("reply", "edit", "react", "info", "delete", "fetch|pull|push"):
            self.assertIn(verb, out)


if __name__ == "__main__":
    unittest.main()
