import json
import unittest

from support.case import GhTestCase
from support.remotes import git

REPO = "testuser/testrepo"
PR = f"https://github.com/{REPO}/pull/7"


class CannedTest(GhTestCase):
    def setUp(self):
        super().setUp()
        git("checkout", "-q", "-b", "feature", cwd=self.work)
        self.github.add_pull(REPO, 7, head="feature", title="T")
        self.github.respond(["pr", "list"], stdout=json.dumps([{"number": 7, "state": "OPEN"}]))
        self.core = self.tmp / "core-config"
        self.ext = self.tmp / "ext-config"

    def comment(self, *args):
        rc, out, err = self.run_gh("comment", *args, TIMVISHER_AGENT="1", TIMVISHER_GH_CORE_CONFIG_DIR=str(self.core),
                                   TIMVISHER_GH_CONFIG_DIR=str(self.ext))
        self.err = err
        return rc, out

    def write(self, root, name, text):
        path = root / "comments" / f"{name}.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def bodies(self):
        return [c["body"] for c in self.github.state["issue_comments"].values()]

    def test_a_name_with_no_such_file_posts_the_canned_comment_untracked(self):
        self.write(self.ext, "arp-review", "@arp review\n")
        rc, out = self.comment("arp-review")
        self.assertEqual(0, rc, self.err)
        [comment_id] = self.github.state["issue_comments"]
        self.assertEqual((f"{PR}#issuecomment-{comment_id}\n", ["@arp review"]), (out, self.bodies()))
        self.assertFalse((self.work / "arp-review").exists())
        self.comment("arp-review")
        self.assertEqual(2, len(self.bodies()))

    def test_the_overlay_is_searched_before_the_core_root(self):
        self.write(self.core, "arp-review", "core\n")
        self.write(self.ext, "arp-review", "overlay\n")
        self.assertEqual(0, self.comment("arp-review")[0], self.err)
        self.assertEqual(["overlay"], self.bodies())
        self.write(self.core, "only-core", "core only\n")
        self.assertEqual(0, self.comment("only-core")[0], self.err)
        self.assertEqual(["overlay", "core only"], self.bodies())

    def test_a_file_of_the_same_name_is_posted_instead(self):
        self.write(self.ext, "arp-review", "canned\n")
        (self.work / "arp-review").write_text("from file\n")
        self.assertEqual(0, self.comment("arp-review")[0], self.err)
        self.assertEqual(["from file"], self.bodies())

    def test_a_canned_comment_can_name_its_pr(self):
        self.github.add_pull(REPO, 8, head="other", title="Other")
        self.write(self.ext, "lgtm", "LGTM\n")
        self.assertEqual(0, self.comment(f"https://github.com/{REPO}/pull/8", "lgtm")[0], self.err)
        self.assertEqual(8, next(iter(self.github.state["issue_comments"].values()))["issue_number"])

    def test_an_unknown_name_is_neither_a_file_nor_canned(self):
        rc, _ = self.comment("no-such-thing")
        self.assertEqual(2, rc)
        self.assertEqual([], self.bodies())

    def test_the_default_roots_find_push_post_hooks_where_the_config_moved(self):
        ide = self.home / ".config/timvisher/ide"
        if ide.is_symlink():
            ide.unlink()
        hook = ide / "python/bin/timvisher_gh.config/orgs/testuser/pr/push/post.d/arp-review"
        hook.parent.mkdir(parents=True)
        log = self.tmp / "hook.log"
        hook.write_text(f"#!/usr/bin/env bash\necho ran >> '{log}'\n")
        hook.chmod(0o755)
        self.github._update(lambda s: s["responses"].clear())
        self.github.respond(["pr", "list"], stdout="[]")
        self.github.respond(["pr", "diff"], stdout="")
        git("commit", "-q", "--allow-empty", "-m", "work", cwd=self.work)
        (self.work / "pr.md").write_text("New\n")
        rc, out, err = self.run_gh("pr", "push", TIMVISHER_AGENT="1", TIMVISHER_GH_CORE_CONFIG_DIR="",
                                   TIMVISHER_GH_CONFIG_DIR="")
        self.assertEqual(0, rc, err)
        self.assertEqual("ran\n", log.read_text())


if __name__ == "__main__":
    unittest.main()
