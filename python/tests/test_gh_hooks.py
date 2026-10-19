import os
import pathlib
import unittest
from unittest import mock

from support.case import GhTestCase
from support.remotes import commit_on_remote, git
from timvisher.gh import hooks, state

REPO = "testuser/testrepo"
PR1 = f"https://github.com/{REPO}/pull/1"

HOOK = """#!/usr/bin/env bash
printf '%s phase=%s hook=%s url=%s head=%s scope=%s open=%s title=%s state=%s\\n' \\
  "${0##*/}" "$TIMVISHER_GH_PHASE" "$TIMVISHER_GH_HOOK" "$TIMVISHER_GH_PR_URL" "$TIMVISHER_GH_HEAD_SHA" \\
  "$TIMVISHER_GH_PATH_SCOPE" "$TIMVISHER_GH_OPEN" "$TIMVISHER_GH_NOTIFY_TITLE" "$TIMVISHER_GH_STATE_DIR" \\
  >> "$HOOK_LOG"
echo hook-stdout
exit {rc}
"""


class HooksTest(GhTestCase):
    def setUp(self):
        super().setUp()
        self.core = self.tmp / "core-config"
        self.ext = self.tmp / "ext-config"
        self.log = self.tmp / "hooks.log"
        self.log.touch()
        fake = self.github.bin / "timvisher_browser"
        fake.write_text("#!/usr/bin/env bash\nprintf '%s\\n' \"$2\"\n")
        fake.chmod(0o755)
        self.github.respond(["pr", "list"], stdout="[]")
        self.github.respond(["pr", "diff"], stdout="README.md\n")
        git("checkout", "-q", "-b", "feature", cwd=self.work)
        git("commit", "-q", "--allow-empty", "-m", "work", cwd=self.work)

    def hook(self, root, relative, rc=0):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(HOOK.replace("{rc}", str(rc)))
        path.chmod(0o755)

    def pr(self, *args):
        rc, out, err = self.run_gh("pr", *args, TIMVISHER_AGENT="1", HOOK_LOG=str(self.log),
                                   TIMVISHER_GH_CORE_CONFIG_DIR=str(self.core), TIMVISHER_GH_CONFIG_DIR=str(self.ext))
        self.err = err
        return rc, out

    def ran(self):
        return [line.split()[0] for line in self.log.read_text().splitlines()]

    def create(self):
        (self.work / "pr.md").write_text("Hook title\n\nHook body\n")
        rc, out = self.pr("push")
        self.assertEqual(0, rc, self.err)
        self.log.write_text("")

    def new_commit(self):
        git("commit", "-q", "--allow-empty", "-m", "more", cwd=self.work)

    def test_push_hooks_run_from_both_roots_and_scopes_in_order_off_stdout(self):
        self.create()
        self.new_commit()
        self.hook(self.core, "orgs/testuser/pr/push/pre.d/10-core-org")
        self.hook(self.ext, "repos/testuser/testrepo/pr/push/pre.d/10-ext-repo")
        self.hook(self.core, "repos/testuser/testrepo/pr/push/post.d/20-core-repo")
        self.hook(self.ext, "orgs/testuser/pr/push/post.d/10-ext-org")
        (self.ext / "orgs/testuser/pr/push/post.d/README").write_text("not a hook\n")
        rc, out = self.pr("push")
        self.assertEqual((0, f"{PR1}\n"), (rc, out), self.err)
        self.assertEqual(["10-core-org", "10-ext-repo", "20-core-repo", "10-ext-org"], self.ran())
        line = self.log.read_text().splitlines()[-1]
        head = git("rev-parse", "HEAD", cwd=self.work)
        store_dir = (self.work / ".timvisher_gh" / "pr").resolve()
        self.assertEqual(f"10-ext-org phase=push hook=post url={PR1} head={head} scope= open=false "
                         f"title={REPO}#1: Hook title state={store_dir}", line)
        self.assertIn("hook-stdout", self.err)
        self.assertTrue(str(store_dir).startswith(str(state.root())))

    def test_pre_hooks_are_skipped_when_already_pushed_and_post_hooks_always_run(self):
        self.create()
        self.hook(self.core, "orgs/testuser/pr/push/pre.d/10-gate")
        self.hook(self.core, "orgs/testuser/pr/push/post.d/10-after")
        rc, _ = self.pr("push", "--open")
        self.assertEqual(0, rc, self.err)
        self.assertEqual(["10-after"], self.ran())
        self.assertIn("open=true", self.log.read_text())

    def test_pre_hooks_are_skipped_when_behind_and_push_exits_4(self):
        self.create()
        commit_on_remote(self.tmp, self.remote, "feature", "ahead on origin")
        self.hook(self.core, "orgs/testuser/pr/push/pre.d/10-gate")
        rc, _ = self.pr("push")
        self.assertEqual(4, rc)
        self.assertEqual([], self.ran())

    def test_a_failing_pre_hook_gates_the_push(self):
        self.create()
        self.new_commit()
        self.hook(self.core, "orgs/testuser/pr/push/pre.d/10-gate", rc=1)
        self.hook(self.core, "orgs/testuser/pr/push/pre.d/20-after")
        self.hook(self.core, "orgs/testuser/pr/push/post.d/10-post")
        before = git("rev-parse", "feature", cwd=self.remote)
        rc, _ = self.pr("push")
        self.assertNotEqual(0, rc)
        self.assertEqual(["10-gate"], self.ran())
        self.assertEqual(before, git("rev-parse", "feature", cwd=self.remote))
        self.assertIn("timvisher_gh_pre_hook_failed", self.err)

    def test_a_failing_post_hook_runs_the_rest_and_exits_nonzero(self):
        self.create()
        self.hook(self.core, "orgs/testuser/pr/push/post.d/10-broken", rc=1)
        self.hook(self.core, "orgs/testuser/pr/push/post.d/20-fine")
        rc, out = self.pr("push")
        self.assertEqual((1, f"{PR1}\n"), (rc, out))
        self.assertEqual(["10-broken", "20-fine"], self.ran())
        self.assertIn("timvisher_gh_post_hook_failed", self.err)

    def test_a_path_scope_fires_only_for_directories_the_pr_touches(self):
        self.create()
        self.github._update(lambda s: s["responses"].clear())
        self.github.respond(["pr", "list"], stdout="[]")
        self.github.respond(["pr", "diff"], stdout="apps/cfctl/main.go\nREADME.md\n")
        self.hook(self.ext, "repos/testuser/testrepo/paths/apps/cfctl/pr/push/post.d/10-cfctl")
        self.hook(self.ext, "repos/testuser/testrepo/paths/apps/other/pr/push/post.d/10-other")
        self.assertEqual(0, self.pr("push")[0], self.err)
        self.assertEqual(["10-cfctl"], self.ran())
        self.assertIn("scope=apps/cfctl ", self.log.read_text())

    def test_creation_runs_pre_hooks_before_and_post_hooks_after(self):
        self.hook(self.core, "orgs/testuser/pr/push/pre.d/10-gate")
        self.hook(self.core, "orgs/testuser/pr/push/post.d/10-after")
        (self.work / "pr.md").write_text("New\n\nBody\n")
        rc, out = self.pr("push")
        self.assertEqual((0, f"{PR1}\n"), (rc, out), self.err)
        lines = self.log.read_text().splitlines()
        self.assertEqual(["10-gate", "10-after"], [line.split()[0] for line in lines])
        self.assertIn("url= ", lines[0])
        self.assertIn(f"url={PR1} ", lines[1])

    def test_a_failing_pre_hook_on_creation_creates_nothing(self):
        self.hook(self.core, "orgs/testuser/pr/push/pre.d/10-gate", rc=1)
        (self.work / "pr.md").write_text("New\n")
        self.assertNotEqual(0, self.pr("push")[0])
        self.assertEqual({}, self.github.state["pulls"])

    def test_the_default_roots_are_python_bin_in_core_and_the_overlay(self):
        with mock.patch.dict(os.environ, {"TIMVISHER_GH_CORE_CONFIG_DIR": "", "TIMVISHER_GH_CONFIG_DIR": ""}):
            core, ext = hooks.roots()
        self.assertEqual("python/bin/timvisher_gh.config", "/".join(core.parts[-3:]))
        self.assertEqual(pathlib.Path.home() / ".config/timvisher/ide/python/bin/timvisher_gh.config", ext)

if __name__ == "__main__":
    unittest.main()
