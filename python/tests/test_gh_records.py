import json
import unittest

from support.case import GhTestCase
from timvisher.gh import record, state

REPO = "testuser/testrepo"
PR = f"https://github.com/{REPO}/pull/7"
COMMON = {"schema_version", "kind", "url", "id", "database_id", "owner", "repo", "author", "created_at",
          "updated_at", "deleted_at", "source", "posted", "github"}


class RecordsTest(GhTestCase):
    def setUp(self):
        super().setUp()
        gh = self.github
        gh.set_now("2026-10-10T09:00:00Z")
        gh.add_pull(REPO, 7, head="feature", title="Fix it", body="Because", author="alice", draft=True,
                    head_sha="a" * 40)
        gh.set_now("2026-10-10T10:00:00Z")
        self.top = gh.add_issue_comment(REPO, 7, "top level", user="bob")
        gh.add_reaction("issue_comment", self.top, "heart", user="testuser")
        gh.add_reaction("issue_comment", self.top, "+1", user="testuser")
        gh.add_reaction("issue_comment", self.top, "+1", user="carol")
        self.root = gh.add_review_comment(REPO, 7, "nit", path="pkg/a.go", line=4, user="carol")
        self.reply = gh.add_review_comment(REPO, 7, "fixed", reply_to=self.root)
        self.thread = gh.thread_of(self.root)
        gh.set_outdated(self.thread)
        self.review = gh.add_review(REPO, 7, user="dave", state="APPROVED", body="LGTM")
        gh.add_issue(REPO, 3, title="Bug", body="It breaks", author="erin")

    def info(self, *args):
        rc, out, err = self.run_gh(*args, TIMVISHER_AGENT="1")
        self.assertEqual(0, rc, err)
        return json.loads(out)

    def calls_since(self, mark):
        return self.github.calls[mark:]

    def test_pr_info_has_every_pr_field(self):
        pr = self.info("pr", "info", PR)
        self.assertEqual(COMMON | {"number", "title", "body", "state", "draft", "base", "head", "head_sha",
                                   "merged_at", "merge_commit", "comments", "threads", "reviews"}, set(pr))
        self.assertEqual((1, "pr", PR, "alice", "2026-10-10T09:00:00Z", 7, "Fix it", "Because", "open", True, "main",
                          "feature", "a" * 40, None, None),
                         (pr["schema_version"], pr["kind"], pr["url"], pr["author"], pr["created_at"], pr["number"],
                          pr["title"], pr["body"], pr["state"], pr["draft"], pr["base"], pr["head"], pr["head_sha"],
                          pr["merged_at"], pr["merge_commit"]))
        self.assertEqual(([f"{PR}#issuecomment-{self.top}"], [f"{PR}#discussion_r{self.root}"],
                          [f"{PR}#pullrequestreview-{self.review}"]),
                         (pr["comments"], pr["threads"], pr["reviews"]))
        self.assertEqual(("testuser", "testrepo", "PR_testuser/testrepo#7", 900007, None, {}, {"path": None,
                                                                                           "authored_paths": []}),
                         (pr["owner"], pr["repo"], pr["id"], pr["database_id"], pr["deleted_at"], pr["posted"],
                          pr["source"]))
        self.assertEqual("feature", pr["github"]["head"]["ref"])

    def test_a_merged_pr(self):
        self.github.add_pull(REPO, 8, head="old", state="closed", merged=True, merged_at="2026-10-11T00:00:00Z",
                             merge_commit_sha="b" * 40)
        pr = self.info("pr", "info", f"https://github.com/{REPO}/pull/8")
        self.assertEqual(("merged", "2026-10-11T00:00:00Z", "b" * 40), (pr["state"], pr["merged_at"], pr["merge_commit"]))

    def test_known_objects_are_never_refetched(self):
        self.info("pr", "info", PR)
        mark = len(self.github.calls)
        self.info("pr", "info", PR)
        self.info("comment", "info", f"{PR}#issuecomment-{self.top}")
        self.assertEqual([], self.calls_since(mark))

    def test_an_unknown_comment_on_a_known_pr_is_fetched_without_refreshing_the_rest(self):
        self.info("pr", "info", PR)
        self.github.set_now("2026-10-12T00:00:00Z")
        newer = self.github.add_issue_comment(REPO, 7, "later", user="bob")
        self.github._update(lambda s: s["pulls"][REPO]["7"].update(title="Renamed on GitHub"))
        self.assertEqual("later", self.info("comment", "info", f"{PR}#issuecomment-{newer}")["body"])
        pr = self.info("pr", "info", PR)
        self.assertEqual("Fix it", pr["title"])
        self.assertIn(f"{PR}#issuecomment-{newer}", pr["comments"])

    def test_components_have_jq_r_semantics(self):
        rc, out, _ = self.run_gh("pr", "info", PR, ".title")
        self.assertEqual((0, "Fix it\n"), (rc, out))
        rc, out, _ = self.run_gh("pr", "info", PR, ".threads")
        self.assertEqual([f"{PR}#discussion_r{self.root}"], json.loads(out))

    def test_issue_info_has_every_issue_field(self):
        issue = self.info("issue", "info", f"https://github.com/{REPO}/issues/3")
        self.assertEqual(COMMON | {"number", "title", "body", "state", "closed_at"}, set(issue))
        self.assertEqual(("issue", 3, "Bug", "It breaks", "open", None, "erin"),
                         (issue["kind"], issue["number"], issue["title"], issue["body"], issue["state"],
                          issue["closed_at"], issue["author"]))

    def test_a_top_level_comment_embeds_its_pr_without_children(self):
        comment = self.info("comment", "info", f"{PR}#issuecomment-{self.top}")
        self.assertEqual(COMMON | {"comment_kind", "pr", "thread", "in_reply_to", "body", "reactions",
                                   "reaction_counts"}, set(comment))
        self.assertEqual(("comment", "issue_comment", None, None, "top level", ["+1", "heart"], "bob"),
                         (comment["kind"], comment["comment_kind"], comment["thread"], comment["in_reply_to"],
                          comment["body"], comment["reactions"], comment["author"]))
        self.assertEqual((2, 1, 0), (comment["reaction_counts"]["+1"], comment["reaction_counts"]["heart"],
                                     comment["reaction_counts"]["eyes"]))
        self.assertEqual((1, "pr", PR), (comment["pr"]["schema_version"], comment["pr"]["kind"], comment["pr"]["url"]))
        self.assertNotIn("comments", comment["pr"])

    def test_a_reply_embeds_its_thread_and_names_its_root(self):
        reply = self.info("comment", "info", f"{PR}#discussion_r{self.reply}")
        self.assertEqual(("review_comment", f"{PR}#discussion_r{self.root}", "fixed", PR),
                         (reply["comment_kind"], reply["in_reply_to"], reply["body"], reply["pr"]["url"]))
        self.assertEqual(("thread", 1), (reply["thread"]["kind"], reply["thread"]["schema_version"]))
        self.assertNotIn("replies", reply["thread"])

    def test_a_threads_root_is_a_comment_too(self):
        root = self.info("comment", "info", f"{PR}#discussion_r{self.root}")
        self.assertEqual(("comment", "review_comment", "nit", f"PRRC_{self.root}", None, "carol"),
                         (root["kind"], root["comment_kind"], root["body"], root["id"], root["in_reply_to"],
                          root["author"]))

    def test_thread_info_has_every_thread_field(self):
        thread = self.info("thread", "info", f"{PR}#discussion_r{self.root}")
        self.assertEqual(COMMON | {"pr", "path", "line", "start_line", "side", "commit", "outdated", "resolved",
                                   "root", "replies"}, set(thread))
        self.assertEqual(("thread", self.thread, "pkg/a.go", 4, None, "RIGHT", "0" * 40, True, False,
                          f"{PR}#discussion_r{self.root}", [f"{PR}#discussion_r{self.reply}"], "carol"),
                         (thread["kind"], thread["id"], thread["path"], thread["line"], thread["start_line"],
                          thread["side"], thread["commit"], thread["outdated"], thread["resolved"], thread["root"],
                          thread["replies"], thread["author"]))
        self.assertEqual(PR, thread["pr"]["url"])

    def test_reviews_and_every_kind_are_exported_with_schema_version(self):
        self.info("pr", "info", PR)
        root = state.root()
        exports = {path.name: json.loads(path.read_text()) for path in root.rglob("*.json")}
        self.assertEqual({"pr.json", "comment.json", "thread.json", "review.json"}, set(exports))
        review = exports["review.json"]
        self.assertEqual(COMMON | {"pr", "state", "body", "submitted_at"}, set(review))
        self.assertEqual(("review", "APPROVED", "LGTM", "dave", "2026-10-10T10:00:00Z", 1),
                         (review["kind"], review["state"], review["body"], review["author"], review["submitted_at"],
                          review["pr"]["schema_version"]))
        self.assertTrue(all(e["schema_version"] == 1 for e in exports.values()))
        self.assertEqual(f"{PR}\n", next(root.rglob("pr.url")).read_text())

    def test_schema_version_pins(self):
        self.assertEqual("Fix it\n", self.run_gh("pr", "info", "--schema-version", "1", PR, ".title")[1])
        rc, out, err = self.run_gh("pr", "info", "--schema-version", "2", PR, TIMVISHER_AGENT="1")
        instruction = json.loads(err.splitlines()[-1])
        self.assertEqual((1, "", "timvisher_gh_schema_version_mismatch"), (rc, out, instruction["code"]))
        self.assertTrue(any("--schema-version 1" in s for s in instruction["suggestions"]))

    def test_help_documents_every_field_the_version_and_the_rules(self):
        for noun, kinds in (("pr", ("pr", "review")), ("issue", ("issue",)), ("comment", ("comment",)),
                            ("thread", ("thread",))):
            rc, out, _ = self.run_gh(noun, "info", "--help")
            self.assertEqual(0, rc)
            for group in ("common", *kinds):
                for name, _ in record.FIELDS[group]:
                    self.assertIn(name, out, (noun, name))
            self.assertIn("schema_version 1", out)
            self.assertIn("Adding a field", out)
            self.assertIn("1  the first version", out)

    def test_a_target_of_another_kind_is_a_usage_error(self):
        rc, _, err = self.run_gh("issue", "info", PR, TIMVISHER_AGENT="1")
        self.assertEqual(2, rc)
        self.assertIn(f"'{PR}' names a pr, so issue info can't use it", err)

    def test_a_pr_github_doesnt_have_is_an_error(self):
        rc, _, err = self.run_gh("pr", "info", f"https://github.com/{REPO}/pull/99", TIMVISHER_AGENT="1")
        self.assertEqual((1, "timvisher_gh_not_found"), (rc, json.loads(err.splitlines()[-1])["code"]))

    def test_a_target_path_starting_with_a_dot_is_a_target_not_a_component(self):
        self.info("pr", "info", PR)
        pr_dir = next(state.root().rglob("pr.json")).parent
        (self.work / ".timvisher_gh").mkdir()
        (self.work / ".timvisher_gh" / "pr").symlink_to(pr_dir)
        (pr_dir / "pr.md").write_text("Fix it\n\nBecause\n")
        mark = len(self.github.calls)
        rc, out, _ = self.run_gh("pr", "info", ".timvisher_gh/pr/pr.md", ".title")
        self.assertEqual((0, "Fix it\n"), (rc, out))
        rc, out, _ = self.run_gh("pr", "info", "./.timvisher_gh/pr/pr.md", ".number")
        self.assertEqual((0, "7\n"), (rc, out))
        self.assertEqual([], self.calls_since(mark))

    def test_pr_info_on_a_childs_file_is_the_pr_and_thread_info_on_a_reply_is_its_thread(self):
        self.info("pr", "info", PR)
        reply_dir = next(p.parent for p in state.root().rglob("comment.json") if "replies" in str(p))
        (reply_dir / "comment.md").write_text("fixed\n")
        self.assertEqual("pr", self.info("pr", "info", str(reply_dir / "comment.md"))["kind"])
        self.assertEqual(self.thread, self.info("thread", "info", str(reply_dir / "comment.md"))["id"])
        self.assertEqual(self.thread, self.info("thread", "info", f"{PR}#discussion_r{self.reply}")["id"])

    def test_owner_and_repo_in_another_case_resolve_to_the_canonical_object(self):
        upper = "https://github.com/TestUser/TestRepo/pull/7"
        pr = self.info("pr", "info", upper)
        self.assertEqual((PR, "testuser", "testrepo"), (pr["url"], pr["owner"], pr["repo"]))
        mark = len(self.github.calls)
        self.info("pr", "info", upper)
        self.assertEqual([], self.calls_since(mark))

    def test_info_on_a_url_needs_no_worktree(self):
        rc, out, _ = self.run_gh("pr", "info", PR, ".title", cwd=self.tmp)
        self.assertEqual((0, "Fix it\n"), (rc, out))
        rc, _, err = self.run_gh("pr", "info", cwd=self.tmp, TIMVISHER_AGENT="1")
        self.assertEqual((1, "timvisher_gh_target_none"), (rc, json.loads(err.splitlines()[-1])["code"]))

    def test_a_bare_info_remembers_the_worktrees_pr(self):
        self.github.respond(["pr", "list"], stdout=json.dumps([{"number": 7, "state": "OPEN"}]))
        self.run_gh("pr", "info", ".number")
        mark = len(self.github.calls)
        rc, out, _ = self.run_gh("pr", "info", ".number")
        self.assertEqual((0, "7\n", []), (rc, out, self.calls_since(mark)))

    def test_an_omitted_target_uses_the_worktree_pr(self):
        self.github.respond(["pr", "list"], stdout=json.dumps([{"number": 7, "state": "OPEN"}]))
        rc, out, _ = self.run_gh("pr", "info", ".number")
        self.assertEqual((0, "7\n"), (rc, out))


if __name__ == "__main__":
    unittest.main()
