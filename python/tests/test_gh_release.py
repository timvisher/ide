import json
import unittest

from support.case import GhTestCase
from support.remotes import git

REPO = "testuser/testrepo"
PR = f"https://github.com/{REPO}/pull/7"

HOOK = """#!/usr/bin/env bash
printf '%s phase=%s hook=%s open=%s merge=%s\\n' "${0##*/}" "$TIMVISHER_GH_PHASE" "$TIMVISHER_GH_HOOK" \\
  "$TIMVISHER_GH_OPEN" "$TIMVISHER_GH_MERGE_COMMIT" >> "$HOOK_LOG"
exit {rc}
"""


class ReleaseTest(GhTestCase):
    def setUp(self):
        super().setUp()
        git("checkout", "-q", "-b", "feature", cwd=self.work)
        self.github.add_pull(REPO, 7, head="feature", title="T")
        self.github.respond(["pr", "list"], stdout=json.dumps([{"number": 7, "state": "OPEN"}]))
        self.ext = self.tmp / "ext-config"
        self.log = self.tmp / "hooks.log"
        self.log.touch()
        self.browser_log = self.tmp / "browser.log"
        fake = self.github.bin / "timvisher_browser"
        fake.write_text("#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> \"$FAKE_BROWSER_LOG\"\n")
        fake.chmod(0o755)
        hook = self.ext / "orgs/testuser/pr/merge/post.d/10-watch"
        hook.parent.mkdir(parents=True)
        hook.write_text(HOOK.replace("{rc}", "0"))
        hook.chmod(0o755)

    def release(self, *args, stdin=""):
        rc, out, err = self.run_gh_as_tim("pr", "release", *args, stdin=stdin,
                                          TIMVISHER_GH_PR_MERGE_POLL_INTERVAL="0", HOOK_LOG=str(self.log),
                                          FAKE_BROWSER_LOG=str(self.browser_log),
                                          TIMVISHER_GH_CORE_CONFIG_DIR=str(self.tmp / "no-core"),
                                          TIMVISHER_GH_CONFIG_DIR=str(self.ext))
        self.err = err
        return rc, out

    def codes(self):
        return [json.loads(line)["code"] for line in self.err.splitlines() if line.startswith('{"type":"instruction"')]

    def test_a_merged_pr_runs_the_merge_post_hooks_with_its_merge_commit(self):
        self.github.update_pull(REPO, 7, merged=True, state="closed", merge_commit_sha="abc123")
        rc, out = self.release(PR, "--open")
        self.assertEqual((0, f"{PR}\n"), (rc, out), self.err)
        self.assertEqual(["10-watch phase=merge hook=post open=true merge=abc123"], self.log.read_text().splitlines())
        self.assertEqual(f"tab {PR}\n", self.browser_log.read_text())
        self.assertIn("timvisher_gh_release_converged", self.codes())
        self.assertEqual("merged\n", self.run_gh("pr", "info", PR, ".state")[1])

    def test_no_watch_skips_the_merge_post_hooks(self):
        self.github.update_pull(REPO, 7, merged=True, state="closed", merge_commit_sha="abc123")
        rc, _ = self.release(PR, "--no-watch")
        self.assertEqual(0, rc, self.err)
        self.assertEqual("", self.log.read_text())
        self.assertIn("timvisher_gh_release_not_watched", self.codes())
        self.assertFalse(self.browser_log.exists())

    def test_an_open_pr_is_merged_then_the_hooks_get_the_new_merge_commit(self):
        rc, _ = self.release(stdin="y\n")
        self.assertEqual(0, rc, self.err)
        self.assertTrue(self.github.state["pulls"][REPO]["7"]["merged"])
        self.assertEqual(["10-watch phase=merge hook=post open=false merge=" + "m" * 40],
                         self.log.read_text().splitlines())

    def test_declining_the_merge_skips_the_watch(self):
        rc, _ = self.release(PR, stdin="n\n")
        self.assertNotEqual(0, rc)
        self.assertEqual("", self.log.read_text())

    def test_a_failing_post_hook_fails_the_release(self):
        self.github.update_pull(REPO, 7, merged=True, state="closed", merge_commit_sha="abc123")
        (self.ext / "orgs/testuser/pr/merge/post.d/10-watch").write_text(HOOK.replace("{rc}", "1"))
        rc, out = self.release(PR)
        self.assertEqual((1, f"{PR}\n"), (rc, out))
        self.assertIn("timvisher_gh_post_hook_failed", self.codes())


if __name__ == "__main__":
    unittest.main()
