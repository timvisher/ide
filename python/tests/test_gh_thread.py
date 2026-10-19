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

    def thread(self, *args):
        rc, out, err = self.run_gh("thread", *args, TIMVISHER_AGENT="1")
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


if __name__ == "__main__":
    unittest.main()
