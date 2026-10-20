import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

from timvisher.testing import fresh_home

ENTRY = pathlib.Path(__file__).resolve().parents[1] / "bin" / "timvisher_gh"
REAL_GIT = next(g for g in ("/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git") if os.access(g, os.X_OK))

FAKE_GH = """#!/usr/bin/env bash
echo "gh $*" >> "$FAKE_LOG"
target_repo=
if [[ $1 == -R ]]
then
  target_repo=$2
  shift 2
fi
if [[ $1 == api && $2 == user ]]
then
  echo testuser
elif [[ $1 == api && $2 == repos/archivedorg/* ]]
then
  echo '{"fork":false,"source":null,"archived":true}'
elif [[ $1 == api && $2 == repos/* ]]
then
  echo '{"fork":true,"source":"upstreamorg/testrepo","archived":false}'
else
  exit 1
fi
"""

FAKE_TIMVISHER_GIT = """#!/usr/bin/env bash
[[ $1 == info && $2 == --json ]] || exit 2
case ${FAKE_TIMVISHER_GIT-} in
  fail)
    echo "info: worktree is not under TIMVISHER_GIT_HOME" >&2
    exit 1
    ;;
  detached)
    echo '{"timvisher_git":{"org":"testuser","repo":"testrepo","branch":null,"branchPath":"main","absPath":"/fake","prefixPath":"testuser/testrepo/main"}}'
    ;;
  *)
    echo '{"timvisher_git":{"org":"testuser","repo":"testrepo","branch":"main","branchPath":"main","absPath":"/fake/testuser/testrepo/main","prefixPath":"testuser/testrepo/main"}}'
    ;;
esac
"""


class InfoTest(unittest.TestCase):
    def setUp(self):
        home = fresh_home()
        home.__enter__()
        self.addCleanup(home.__exit__, None, None, None)

        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = pathlib.Path(tmp.name)
        self.log = self.tmp / "log"
        self.log.touch()

        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        (self.bin / "git").symlink_to(REAL_GIT)
        for name, body in (("gh", FAKE_GH), ("timvisher_git", FAKE_TIMVISHER_GIT)):
            path = self.bin / name
            path.write_text(body)
            path.chmod(0o755)

        self.repo = self.tmp / "repo"
        self.repo.mkdir()
        for args in (
            ("init", "-q"),
            ("remote", "add", "origin", "https://github.com/testuser/testrepo.git"),
            ("commit", "-q", "--allow-empty", "-m", "init"),
        ):
            subprocess.run([REAL_GIT, *args], cwd=self.repo, check=True)
        self.elsewhere = self.tmp / "not-a-repo"
        self.elsewhere.mkdir()

    def run_gh(self, *args, cwd=None, **env):
        done = subprocess.run(
            [sys.executable, str(ENTRY), *args],
            cwd=cwd or self.repo,
            env={**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}", "FAKE_LOG": str(self.log), **env},
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return done.returncode, done.stdout, done.stderr

    def gh_calls(self):
        return self.log.read_text().splitlines()

    def test_no_arguments_prints_usage_on_stderr_and_exits_2(self):
        rc, out, err = self.run_gh()
        self.assertEqual((2, ""), (rc, out))
        self.assertIn("Usage:", err)

    def test_help_prints_usage_on_stdout(self):
        for flag in ("-h", "--help", "help"):
            rc, out, _ = self.run_gh(flag)
            self.assertEqual(0, rc, flag)
            self.assertIn("Usage:", out)

    def test_help_works_outside_a_git_repository(self):
        rc, out, err = self.run_gh("--help", cwd=self.elsewhere)
        self.assertEqual(0, rc)
        self.assertIn("Usage:", out)
        self.assertNotIn("Not in a git repository", err)

    def test_help_wins_over_a_bad_c_path(self):
        rc, out, _ = self.run_gh("-C", str(self.tmp / "no-such-dir"), "--help", cwd=self.tmp)
        self.assertEqual(0, rc)
        self.assertIn("Usage:", out)

    def test_an_unknown_command_prints_usage_and_exits_2(self):
        rc, _, err = self.run_gh("bogus")
        self.assertEqual(2, rc)
        self.assertIn("Usage:", err)
        self.assertIn("Unknown command: 'bogus'", err)

    def test_info_json_merges_the_timvisher_git_blob_with_the_gh_fields(self):
        rc, out, _ = self.run_gh("info", "--json")
        self.assertEqual(0, rc)
        blob = json.loads(out)
        self.assertEqual("testuser", blob["timvisher_git"]["org"])
        self.assertEqual("main", blob["timvisher_git"]["branchPath"])
        self.assertEqual(
            {
                "me": "testuser",
                "archived": False,
                "forkNetwork": {"mainRepo": "upstreamorg/testrepo", "mainOwner": "upstreamorg"},
            },
            blob["timvisher_gh"],
        )

    def test_info_json_fetches_the_repository_once(self):
        self.run_gh("info", "--json")
        self.assertEqual(1, sum(call.startswith("gh api repos/") for call in self.gh_calls()))

    def test_info_json_carries_a_null_branch_through_for_a_detached_worktree(self):
        rc, out, _ = self.run_gh("info", "--json", FAKE_TIMVISHER_GIT="detached")
        self.assertEqual(0, rc)
        blob = json.loads(out)
        self.assertIsNone(blob["timvisher_git"]["branch"])
        self.assertEqual("testuser", blob["timvisher_gh"]["me"])

    def test_info_json_fails_when_timvisher_git_cannot_resolve_the_worktree(self):
        rc, out, err = self.run_gh("info", "--json", FAKE_TIMVISHER_GIT="fail")
        self.assertEqual((1, ""), (rc, out))
        self.assertIn("Unable to query timvisher_git context", err)

    def test_outside_a_worktree_info_leaves_out_what_needs_one(self):
        for args in (["info"], ["info", "--json"]):
            rc, out, err = self.run_gh(*args, cwd=self.elsewhere)
            self.assertEqual(0, rc, err)
            self.assertEqual({"timvisher_gh": {"me": "testuser"}}, json.loads(out))
        self.assertEqual((0, "testuser\n"), self.run_gh("info", ".me", cwd=self.elsewhere)[:2])
        rc, out, err = self.run_gh("info", ".archived", cwd=self.elsewhere)
        self.assertEqual((1, ""), (rc, out))
        self.assertIn("needs a repository", err)

    def test_c_resolves_context_from_the_path_not_the_cwd(self):
        rc, out, _ = self.run_gh("-C", str(self.repo), "info", ".me", cwd=self.tmp)
        self.assertEqual((0, "testuser\n"), (rc, out))
        self.assertIn("gh -R testuser/testrepo api user --jq .login", self.gh_calls())

    def test_c_after_the_command_is_not_a_context_flag(self):
        rc, _, err = self.run_gh("info", "-C", str(self.repo), cwd=self.tmp)
        self.assertEqual(2, rc)
        self.assertIn("unexpected argument '-C'", err)
        self.assertNotIn("fatal:", err)

    def test_c_without_a_path_is_a_usage_error(self):
        rc, _, err = self.run_gh("-C")
        self.assertEqual(2, rc)
        self.assertIn("requires a <path> argument", err)

    def test_c_with_an_empty_path_is_a_usage_error(self):
        rc, _, err = self.run_gh("-C", "", "info", ".me")
        self.assertEqual(2, rc)
        self.assertIn("non-empty", err)

    def test_c_with_a_missing_path_reports_the_path(self):
        rc, _, err = self.run_gh("-C", str(self.tmp / "no-such-dir"), "info", ".me")
        self.assertEqual(1, rc)
        self.assertIn("unable to enter", err)

    def test_c_with_an_existing_non_repo_path_reports_no_repository(self):
        rc, _, err = self.run_gh("-C", str(self.elsewhere), "info", ".me")
        self.assertEqual(1, rc)
        self.assertIn("Not in a git repository", err)
        self.assertNotIn("unable to enter", err)

    def test_info_rejects_an_extra_positional_argument(self):
        rc, _, err = self.run_gh("info", ".me", str(self.repo))
        self.assertEqual(2, rc)
        self.assertIn("unexpected argument", err)

    def test_bare_info_is_the_json_block(self):
        rc, out, err = self.run_gh("info")
        self.assertEqual(0, rc, err)
        self.assertEqual(json.loads(self.run_gh("info", "--json")[1]), json.loads(out))

    def test_json_encodes_a_field(self):
        self.assertEqual((0, '"testuser"\n'), self.run_gh("info", "--json", ".me")[:2])
        self.assertEqual((0, '"testuser"\n'), self.run_gh("info", ".me", "--json")[:2])
        self.assertEqual((0, "false\n"), self.run_gh("info", "--json", ".archived")[:2])
        self.assertEqual((0, '"upstreamorg"\n'), self.run_gh("info", "--json", ".forkNetwork.mainOwner")[:2])

    def test_an_unknown_info_field_is_a_usage_error(self):
        rc, _, err = self.run_gh("info", ".bogus")
        self.assertEqual(2, rc)
        self.assertIn("Unknown info field: '.bogus'", err)

    def test_info_archived_is_false_for_a_live_repository(self):
        self.assertEqual((0, "false\n"), self.run_gh("info", ".archived")[:2])

    def test_info_fork_network_fields_name_the_fork_source(self):
        self.assertEqual((0, "upstreamorg/testrepo\n"), self.run_gh("info", ".forkNetwork.mainRepo")[:2])
        self.assertEqual((0, "upstreamorg\n"), self.run_gh("info", ".forkNetwork.mainOwner")[:2])

    def test_r_answers_for_a_repository_with_no_worktree(self):
        rc, out, _ = self.run_gh("-R", "archivedorg/oldrepo", "info", ".archived", cwd=self.tmp)
        self.assertEqual((0, "true\n"), (rc, out))
        self.assertTrue(any(call.startswith("gh api repos/archivedorg/oldrepo") for call in self.gh_calls()))

    def test_r_main_repo_of_a_repository_that_is_not_a_fork_is_itself(self):
        rc, out, _ = self.run_gh("-R", "archivedorg/oldrepo", "info", ".forkNetwork.mainRepo", cwd=self.tmp)
        self.assertEqual((0, "archivedorg/oldrepo\n"), (rc, out))

    def test_repo_accepts_github_com_owner_repo(self):
        rc, out, _ = self.run_gh("--repo", "github.com/someorg/somerepo", "info", ".forkNetwork.mainRepo", cwd=self.tmp)
        self.assertEqual((0, "upstreamorg/testrepo\n"), (rc, out))

    def test_c_and_r_together_are_rejected(self):
        rc, _, err = self.run_gh("-C", str(self.repo), "-R", "someorg/somerepo", "info", ".me")
        self.assertEqual(2, rc)
        self.assertIn("mutually exclusive", err)

    def test_r_is_rejected_for_commands_that_need_a_worktree(self):
        rc, _, err = self.run_gh("-R", "someorg/somerepo", "pr", "ready")
        self.assertEqual(2, rc)
        self.assertIn("only supported with 'info'", err)

    def test_r_rejects_a_value_that_is_not_owner_repo(self):
        rc, _, err = self.run_gh("-R", "just-an-owner", "info", ".me", cwd=self.tmp)
        self.assertEqual(2, rc)
        self.assertIn("is not OWNER/REPO", err)

    def test_r_info_is_the_block_without_the_worktree_fields(self):
        for args in (["info"], ["info", "--json"]):
            rc, out, err = self.run_gh("-R", "archivedorg/oldrepo", *args, cwd=self.tmp)
            self.assertEqual(0, rc, err)
            self.assertEqual({"timvisher_gh": {"me": "testuser", "archived": True,
                                               "forkNetwork": {"mainRepo": "archivedorg/oldrepo",
                                                               "mainOwner": "archivedorg"}}}, json.loads(out))

    def test_r_without_an_argument_is_a_usage_error(self):
        rc, _, err = self.run_gh("-R", cwd=self.tmp)
        self.assertEqual(2, rc)
        self.assertIn("requires an OWNER/REPO argument", err)

    def test_errors_are_aictl_instructions(self):
        _, _, err = self.run_gh("-R", "just-an-owner", "info", ".me", cwd=self.tmp, TIMVISHER_AGENT="1")
        instruction = json.loads(err.splitlines()[-1])
        self.assertEqual(("instruction", "error", "timvisher_gh_usage"),
                         (instruction["type"], instruction["level"], instruction["code"]))
        self.assertIn("See 'timvisher_gh --help'", instruction["suggestions"])

    def test_a_failing_gh_call_is_an_error(self):
        (self.bin / "gh").write_text("#!/usr/bin/env bash\nexit 1\n")
        rc, out, err = self.run_gh("info", ".archived")
        self.assertEqual((1, ""), (rc, out))
        self.assertIn("Unable to query repo metadata for testuser/testrepo", err)

    def test_info_leaves_no_state_behind(self):
        self.run_gh("info", ".me")
        self.assertFalse((self.repo / ".timvisher_gh").exists())

    def test_the_upstream_remote_wins_over_origin_without_a_tracking_remote(self):
        subprocess.run([REAL_GIT, "remote", "add", "upstream", "git@github.com:upstreamorg/testrepo.git"],
                       cwd=self.repo, check=True)
        self.run_gh("info", ".me")
        self.assertIn("gh -R upstreamorg/testrepo api user --jq .login", self.gh_calls())


if __name__ == "__main__":
    unittest.main()
