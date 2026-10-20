import pathlib
import tempfile
import unittest

from timvisher.gh import store


class NamesTest(unittest.TestCase):
    def test_stamps_are_utc_with_dashes(self):
        self.assertEqual("2026-10-10T10-01-00+0000", store.stamp("2026-10-10T10:01:00Z"))
        self.assertEqual("2026-10-10T14-01-00+0000", store.stamp("2026-10-10T10:01:00-04:00"))

    def test_authors_keep_only_letters_digits_and_dashes(self):
        self.assertEqual("dependabot-bot", store.author("dependabot[bot]"))
        self.assertEqual("a-b", store.author("--a__.b--"))
        self.assertEqual("tim-visher-ddog", store.author("tim-visher_ddog"))

    def test_slugs_turn_controls_and_slashes_into_single_spaces(self):
        self.assertEqual("nit: use x y here", store.slug("nit:\tuse  x/y\n\nhere"))
        self.assertEqual("a b c", store.slug("a\x07b\r\nc"))

    def test_slugs_drop_leading_space_dot_dash_and_trailing_space_dot(self):
        self.assertEqual("hello -", store.slug(" .-hello -. "))
        self.assertEqual("", store.slug(" ... "))

    def test_slugs_are_cut_to_60_characters_then_cleaned(self):
        self.assertEqual("x" * 60, store.slug("x" * 80))
        self.assertEqual("a" * 58, store.slug("a" * 58 + " .b" + "c" * 10))

    def test_comment_names(self):
        self.assertEqual("2026-10-10T10-01-00+0000-alice-LGTM, ship it",
                         store.comment_name("2026-10-10T10:01:00Z", "alice", "LGTM, ship it."))

    def test_names_fit_255_bytes_without_splitting_characters(self):
        name = store.comment_name("2026-10-10T10:01:00Z", "a" * 200, "é" * 60)
        self.assertLessEqual(len(name.encode("utf-8")), 255)
        name.encode("utf-8").decode("utf-8")
        self.assertTrue(name.startswith("2026-10-10T10-01-00+0000-" + "a" * 200 + "-é"))

    def test_thread_names_slug_the_anchor_path(self):
        self.assertEqual("2026-10-10T10-01-00+0000-alice-pkg-a.go-L4",
                         store.thread_name("2026-10-10T10:01:00Z", "alice", "pkg/a.go", 4))
        long = store.thread_name("2026-10-10T10:01:00Z", "alice", "d/" * 50 + "f.go", 12)
        self.assertTrue(long.endswith("-L12"))
        self.assertEqual("d-" * 30, long.split("alice-")[1][:60])

    def test_review_names(self):
        self.assertEqual("2026-10-10T10-01-00+0000-bob-review", store.review_name("2026-10-10T10:01:00Z", "bob"))

    def test_keys(self):
        pr = store.pr_key("O", "R", 7)
        self.assertEqual("github.com/O/R/pull/7", pr)
        self.assertEqual("github.com/O/R/issues/3", store.issue_key("O", "R", 3))
        self.assertEqual("github.com/O/R/pull/7/threads/t/replies/r",
                         store.child_key(store.child_key(pr, "threads", "t"), "replies", "r"))

    def test_a_taken_name_gets_a_counter(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "k").mkdir()
            self.assertEqual("k-2", store.unique(root, "k"))
            self.assertEqual("k-3", store.unique(root, "k", taken={"k-2"}))
            self.assertEqual("fresh", store.unique(root, "fresh"))


if __name__ == "__main__":
    unittest.main()
