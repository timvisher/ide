import json
import unittest

from support.case import GhTestCase
from support.remotes import git
from timvisher.gh import state

REPO = "testuser/testrepo"
PR = f"https://github.com/{REPO}/pull/7"


class ThreadTest(GhTestCase):
    def setUp(self):
        super().setUp()
        git("checkout", "-q", "-b", "feature", cwd=self.work)
        self.github.add_pull(REPO, 7, head="feature", title="T", head_sha="c" * 40)
        self.github.respond(["pr", "list"], stdout=json.dumps([{"number": 7, "state": "OPEN"}]))

    def thread(self, *args, stdin=None):
        rc, out, err = self.run_gh("thread", *args, TIMVISHER_AGENT="1", stdin=stdin)
        self.err = err
        return rc, out

    def codes(self):
        return [json.loads(line)["code"] for line in self.err.splitlines() if line.startswith('{"type":"instruction"')]

    def write(self, name, text):
        path = self.work / name
        path.write_text(text)
        return path

    def roots(self):
        return [c for c in self.github.state["review_comments"].values() if not c.get("in_reply_to_id")]

    def test_a_pr_target_with_an_anchor_creates_a_thread_on_the_prs_head(self):
        source = self.write("nit.md", "Rename this\n")
        rc, out = self.thread(PR, str(source), "--path", "pkg/a.go", "--line", "12")
        self.assertEqual(0, rc, self.err)
        [root] = self.roots()
        self.assertEqual((f"{PR}#discussion_r{root['id']}\n", "Rename this", "pkg/a.go", 12, "RIGHT", "c" * 40, None),
                         (out, root["body"], root["path"], root["line"], root["side"], root["commit_id"],
                          root["start_line"]))
        self.assertTrue(source.is_symlink())
        self.assertIn("/threads/", str(source.resolve()))
        self.assertEqual("root-comment.md", source.resolve().name)

    def test_a_new_thread_anchors_to_the_prs_current_head(self):
        self.run_gh("pr", "info", PR)
        self.github._update(lambda s: s["pulls"][REPO]["7"].update(head_sha="d" * 40))
        self.assertEqual(0, self.thread(PR, str(self.write("n.md", "x\n")), "--path", "a", "--line", "1")[0], self.err)
        self.assertEqual(["d" * 40], [r["commit_id"] for r in self.roots()])

    def test_a_new_thread_past_the_first_page_of_threads_is_tracked(self):
        self.github.add_review_comment(REPO, 7, "one", user="bob")
        self.github.add_review_comment(REPO, 7, "two", path="b.go", user="bob")
        self.github._update(lambda s: s.update(thread_page_size=1))
        source = self.write("n.md", "third\n")
        self.assertEqual(0, self.thread(PR, str(source), "--path", "c.go", "--line", "3")[0], self.err)
        self.assertTrue(source.is_symlink())

    def test_resolve_on_a_legacy_adopted_thread(self):
        root = self.github.add_review_comment(REPO, 7, "nit")
        source = self.write("nit.md", "nit\n")
        self.write("nit.md.url", f"{PR}#discussion_r{root}\n")
        rc, _, err = self.run_gh("comment", str(source), TIMVISHER_AGENT="1")
        self.assertEqual(0, rc, err)
        self.assertEqual(0, self.thread("resolve", str(source))[0], self.err)
        self.assertTrue(self.github.state["threads"][self.github.thread_of(root)]["resolved"])

    def test_a_multi_line_anchor_on_the_left_side(self):
        rc, _ = self.thread(str(self.write("n.md", "x\n")), "--path", "a.go", "--line", "9", "--start-line", "5",
                            "--side", "left")
        self.assertEqual(0, rc, self.err)
        [root] = self.roots()
        self.assertEqual((9, 5, "LEFT"), (root["line"], root["start_line"], root["side"]))

    def test_creation_needs_an_anchor(self):
        rc, _ = self.thread(PR, str(self.write("n.md", "x\n")))
        self.assertEqual(2, rc)
        self.assertEqual([], self.roots())

    def test_a_bad_side_or_line_is_a_usage_error(self):
        self.assertEqual(2, self.thread(str(self.write("n.md", "x\n")), "--path", "a", "--line", "x")[0])
        self.assertEqual(2, self.thread(str(self.write("n.md", "x\n")), "--path", "a", "--line", "3",
                                        "--side", "up")[0])

    def test_rerunning_posts_nothing_and_a_tracked_file_updates_the_root(self):
        source = self.write("nit.md", "First\n")
        self.thread(PR, str(source), "--path", "a.go", "--line", "1")
        source.write_text("Second\n")
        rc, out = self.thread(str(source))
        self.assertEqual(0, rc, self.err)
        self.assertEqual(["Second"], [r["body"] for r in self.roots()])
        self.assertEqual(1, len(self.github.state["review_comments"]))

    def test_a_thread_target_with_its_file_updates_the_root(self):
        source = self.write("nit.md", "First\n")
        self.thread(PR, str(source), "--path", "a.go", "--line", "1")
        [root] = self.roots()
        source.write_text("Via target\n")
        self.assertEqual(0, self.thread(f"{PR}#discussion_r{root['id']}", str(source))[0], self.err)
        self.assertEqual(["Via target"], [r["body"] for r in self.roots()])

    def test_edit_updates_and_errors_for_an_unposted_file(self):
        source = self.write("nit.md", "First\n")
        self.thread(PR, str(source), "--path", "a.go", "--line", "1")
        source.write_text("Edited\n")
        self.assertEqual(0, self.thread("edit", str(source))[0], self.err)
        self.assertEqual(["Edited"], [r["body"] for r in self.roots()])
        rc, _ = self.thread("edit", str(self.write("other.md", "x\n")))
        self.assertEqual((1, ["timvisher_gh_thread_missing"]), (rc, self.codes()))

    def test_resolve_and_unresolve_are_no_ops_when_github_matches(self):
        root = self.github.add_review_comment(REPO, 7, "nit", user="bob")
        url = f"{PR}#discussion_r{root}"
        thread_id = self.github.thread_of(root)
        self.assertEqual((0, f"{url}\n"), self.thread("resolve", url), self.err)
        self.assertTrue(self.github.state["threads"][thread_id]["resolved"])
        mark = len(self.github.calls)
        self.assertEqual(0, self.thread("resolve", url)[0])
        self.assertEqual([], [c for c in self.github.calls[mark:]
                              if "mutation" in c.get("fields", {}).get("query", "")])
        self.assertEqual(0, self.thread("resolve", "--unresolve", url)[0], self.err)
        self.assertFalse(self.github.state["threads"][thread_id]["resolved"])
        rc, out, _ = self.run_gh("thread", "info", url, ".resolved")
        self.assertEqual("false\n", out)

    def test_resolve_on_a_tracked_file(self):
        source = self.write("nit.md", "x\n")
        self.thread(PR, str(source), "--path", "a.go", "--line", "1")
        self.assertEqual(0, self.thread("resolve", str(source))[0], self.err)
        self.assertTrue(all(t["resolved"] for t in self.github.state["threads"].values()))

    def test_resolve_needs_a_thread(self):
        self.assertEqual(2, self.thread("resolve", PR)[0])

    def test_pull_records_outdated_and_writes_githubs_change(self):
        root = self.github.add_review_comment(REPO, 7, "nit")
        url = f"{PR}#discussion_r{root}"
        self.run_gh("pr", "pull")
        self.github.set_outdated(self.github.thread_of(root))
        self.github._update(lambda s: s["review_comments"][str(root)].update(body="nit, edited"))
        self.assertEqual(0, self.thread("pull", url)[0], self.err)
        rc, out, _ = self.run_gh("thread", "info", url, ".outdated")
        self.assertEqual("true\n", out)
        self.assertEqual(["nit, edited\n"], [p.read_text() for p in state.root().rglob("root-comment.md")])

    def test_fetch_writes_no_files(self):
        root = self.github.add_review_comment(REPO, 7, "nit")
        url = f"{PR}#discussion_r{root}"
        self.assertEqual((0, f"{url}\n"), self.thread("fetch", url), self.err)
        self.assertEqual([], list(state.root().rglob("root-comment.md")))

    def test_replies_go_through_comment(self):
        source = self.write("nit.md", "x\n")
        self.thread(PR, str(source), "--path", "a.go", "--line", "1")
        [root] = self.roots()
        rc, out, err = self.run_gh("comment", "reply", f"{PR}#discussion_r{root['id']}",
                                   str(self.write("reply.md", "done\n")), TIMVISHER_AGENT="1")
        self.assertEqual(0, rc, err)
        rc, out, _ = self.run_gh("thread", "info", f"{PR}#discussion_r{root['id']}", ".replies | length")
        self.assertEqual("1\n", out)

    def test_plan_changes_nothing(self):
        rc, out = self.thread(PR, str(self.write("n.md", "x\n")), "--path", "a", "--line", "2", "--plan")
        self.assertEqual(0, rc, self.err)
        self.assertIn("+ thread", out)
        self.assertEqual([], self.roots())

    def build(self, *, reply_user="testuser"):
        root = self.github.add_review_comment(REPO, 7, "nit", review=True)
        first = self.github.add_review_comment(REPO, 7, "fixed", reply_to=root, user=reply_user, review=True)
        second = self.github.add_review_comment(REPO, 7, "thanks", reply_to=root)
        return root, first, second

    def deletes(self):
        return [int(c["path"].rsplit("/", 1)[1]) for c in self.github.calls if c.get("method") == "DELETE"]

    def deleted_at(self, noun, url):
        rc, out, err = self.run_gh(noun, "info", url, ".deleted_at")
        self.assertEqual(0, rc, err)
        return None if out.strip() == "null" else out.strip()

    def test_delete_deletes_replies_newest_first_then_the_root_and_archives_each_copy(self):
        root, first, second = self.build()
        reviews = sorted(self.github.state["reviews"])
        self.assertEqual(0, self.run_gh("pr", "pull", PR)[0])
        url = f"{PR}#discussion_r{root}"
        self.assertEqual((0, ""), self.thread("delete", "--force", url), self.err)
        self.assertEqual(([second, first, root], {}, {}, {}),
                         (self.deletes(), self.github.state["review_comments"], self.github.state["threads"],
                          self.github.state["reviews"]))
        self.assertIn("timvisher_gh_deleted", self.codes())
        self.assertTrue(self.deleted_at("thread", url))
        for reply in (first, second):
            self.assertTrue(self.deleted_at("comment", f"{PR}#discussion_r{reply}"))
        for review in reviews:
            self.assertTrue(self.deleted_at("review", f"{PR}#pullrequestreview-{review}"))
        self.assertEqual([], [p for p in state.root().rglob("root-comment.md") if "/archive/" not in str(p)])

    def test_a_reply_url_names_its_whole_thread(self):
        root, first, second = self.build()
        self.assertEqual(0, self.thread("delete", "--force", f"{PR}#discussion_r{first}")[0], self.err)
        self.assertEqual([second, first, root], self.deletes())

    def test_delete_prompts_naming_other_peoples_comments_and_follows_the_answer(self):
        root, _, _ = self.build(reply_user="bob")
        url = f"{PR}#discussion_r{root}"
        self.assertEqual((0, ""), self.thread("delete", url, stdin="n\n"))
        self.assertIn(f"Delete the thread {url} and its 3 comments, including comments by bob? [y/N]", self.err)
        self.assertEqual((["timvisher_gh_delete_skipped"], []), (self.codes(), self.deletes()))
        self.assertEqual(0, self.thread("delete", url, stdin="y\n")[0], self.err)
        self.assertEqual({}, self.github.state["threads"])

    def test_force_refuses_a_thread_with_anyone_elses_comment(self):
        root, _, _ = self.build(reply_user="bob")
        rc, _ = self.thread("delete", "--force", f"{PR}#discussion_r{root}")
        self.assertEqual((2, ["timvisher_gh_delete_not_yours"], []), (rc, self.codes(), self.deletes()))

    def test_plan_lists_what_it_would_delete_and_deletes_nothing(self):
        root, first, second = self.build()
        rc, out = self.thread("delete", "--plan", f"{PR}#discussion_r{root}")
        self.assertEqual(0, rc, self.err)
        self.assertEqual([f"- comment {PR}#discussion_r{c}  delete" for c in (second, first, root)]
                         + [f"- thread  {PR}#discussion_r{root}  delete"], out.splitlines())
        self.assertEqual([], self.deletes())

    def test_a_thread_already_gone_is_reported_and_archived(self):
        root, _, _ = self.build()
        url = f"{PR}#discussion_r{root}"
        self.assertEqual(0, self.run_gh("pr", "pull", PR)[0])
        self.assertEqual(0, self.thread("delete", "--force", url)[0], self.err)
        self.assertEqual((0, ""), self.thread("delete", "--force", url), self.err)
        self.assertEqual(["timvisher_gh_already_deleted"], self.codes())
        self.assertTrue(self.deleted_at("thread", url))

    def test_a_failed_delete_stops_reports_whats_left_and_a_rerun_finishes(self):
        root, first, second = self.build()
        self.assertEqual(0, self.run_gh("pr", "pull", PR)[0])
        self.github._update(lambda s: s.update(fail_deletes=[first]))
        url = f"{PR}#discussion_r{root}"
        rc, _ = self.thread("delete", "--force", url)
        self.assertEqual((1, [second, first]), (rc, self.deletes()), self.err)
        self.assertIn("timvisher_gh_thread_delete_incomplete", self.codes())
        self.assertIn(f"still on GitHub: {PR}#discussion_r{first}, {url}", self.err)
        self.assertEqual([root, first], self.github.state["threads"][self.github.thread_of(root)]["comments"])
        self.assertTrue(self.deleted_at("comment", f"{PR}#discussion_r{second}"))
        self.assertEqual((None, None), (self.deleted_at("thread", url),
                                        self.deleted_at("comment", f"{PR}#discussion_r{first}")))
        rc, out, _ = self.run_gh("thread", "info", url, ".root")
        self.assertEqual(f"{url}\n", out)
        self.github._update(lambda s: s.update(fail_deletes=[]))
        self.assertEqual(0, self.thread("delete", "--force", url)[0], self.err)
        self.assertEqual(({}, {}), (self.github.state["threads"], self.github.state["reviews"]))
        self.assertTrue(self.deleted_at("thread", url))

    def test_help_documents_delete(self):
        rc, out = self.thread("--help")
        self.assertIn("thread delete [--force] [--plan] <target>", out)


if __name__ == "__main__":
    unittest.main()
