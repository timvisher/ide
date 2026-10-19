import contextlib
import io
import json
import os
import unittest
from unittest import mock

from timvisher.gh import state, store, sync
from timvisher.gh.errors import Exit
from timvisher.testing import fresh_home

URL = "https://github.com/O/R/pull/7"


class Adapter:
    managed = ("title", "body")

    def __init__(self, remote, source):
        self.remote = dict(remote)
        self.source = None if source is None else dict(source)
        self.pushes, self.writes, self.fetches = [], [], 0
        self.on_fetch = None
        self.on_push = None

    def fetch(self, item):
        self.fetches += 1
        if self.on_fetch:
            self.on_fetch(self)
        return dict(self.remote)

    def read_source(self, item):
        return None if self.source is None else dict(self.source)

    def write_source(self, item, values):
        self.writes.append(dict(values))
        self.source = dict(values)

    def push(self, item, values):
        self.pushes.append(dict(values))
        self.remote.update(values)
        if self.on_push:
            self.on_push(self)


class SyncTest(unittest.TestCase):
    def setUp(self):
        home = fresh_home()
        home.__enter__()
        self.addCleanup(home.__exit__, None, None, None)
        patcher = mock.patch.dict(os.environ, {"TIMVISHER_AGENT": "1"})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.state = state.open_state()
        self.addCleanup(self.state.close)
        with self.state.write() as db:
            store.register(db, id="PR_7", kind="pr", url=URL, owner="O", repo="R", number=7,
                           store_path="github.com/O/R/pull/7")

    def setup(self, base, source, remote, mine=True):
        if base is not None:
            with self.state.write() as db:
                for name, value in base.items():
                    store.set_base(db, "PR_7", name, value, "t0")
        adapter = Adapter(remote, source)
        return sync.Item("PR_7", "pr", URL, adapter, mine), adapter

    def run_engine(self, verb, item, **options):
        out, err = io.StringIO(), io.StringIO()
        engine = sync.Engine(self.state, verb, now="t1", rerun=f"timvisher_gh pr {verb}", out=out, **options)
        with contextlib.redirect_stderr(err):
            try:
                rc = engine.run([item])
            except Exit as stop:
                rc = stop.status
        self.stderr = err.getvalue()
        instructions = [json.loads(line) for line in self.stderr.splitlines() if line.startswith("{")]
        return rc, out.getvalue(), instructions

    def bases(self):
        return store.bases(self.state.db, "PR_7")

    BASE = {"title": "T", "body": "B"}

    def test_same_and_same_does_nothing_for_every_verb(self):
        for verb in ("pull", "push", "sync", "edit"):
            with self.subTest(verb=verb):
                item, adapter = self.setup(self.BASE, dict(self.BASE), dict(self.BASE))
                self.assertEqual(0, self.run_engine(verb, item)[0])
                self.assertEqual(([], []), (adapter.pushes, adapter.writes))

    def test_changed_here_only_is_sent_by_push_sync_edit_and_reported_by_pull(self):
        for verb, pushed in (("pull", False), ("push", True), ("sync", True), ("edit", True)):
            with self.subTest(verb=verb):
                item, adapter = self.setup(self.BASE, {"title": "T2", "body": "B"}, dict(self.BASE))
                rc, _, instructions = self.run_engine(verb, item)
                self.assertEqual(0, rc)
                self.assertEqual([{"title": "T2"}] if pushed else [], adapter.pushes)
                self.assertEqual([], adapter.writes)
                if pushed:
                    self.assertEqual("T2", self.bases()["title"])
                else:
                    self.assertEqual(["timvisher_gh_unpushed"], [i["code"] for i in instructions])
                    self.assertEqual("T", self.bases()["title"])

    def test_changed_on_github_only_is_written_by_pull_and_sync_and_refused_by_push_and_edit(self):
        for verb, written in (("pull", True), ("sync", True), ("push", False), ("edit", False)):
            with self.subTest(verb=verb):
                item, adapter = self.setup(self.BASE, dict(self.BASE), {"title": "T", "body": "B2"})
                rc, _, instructions = self.run_engine(verb, item)
                if written:
                    self.assertEqual((0, [{"title": "T", "body": "B2"}], "B2"), (rc, adapter.writes, self.bases()["body"]))
                else:
                    self.assertEqual((4, [], [], "B"), (rc, adapter.writes, adapter.pushes, self.bases()["body"]))
                    self.assertEqual("timvisher_gh_push_refused", instructions[-1]["code"])

    def test_changed_to_the_same_value_on_both_sides_records_the_new_base(self):
        for verb in ("pull", "push", "sync", "edit"):
            with self.subTest(verb=verb):
                item, adapter = self.setup(self.BASE, {"title": "T", "body": "B2"}, {"title": "T", "body": "B2"})
                self.assertEqual(0, self.run_engine(verb, item)[0])
                self.assertEqual(([], [], "B2"), (adapter.pushes, adapter.writes, self.bases()["body"]))

    def test_changed_differently_on_both_sides_is_a_decision_for_every_verb(self):
        for verb in ("pull", "push", "sync", "edit"):
            with self.subTest(verb=verb):
                item, adapter = self.setup(self.BASE, {"title": "T", "body": "mine"}, {"title": "T", "body": "theirs"})
                rc, out, instructions = self.run_engine(verb, item)
                self.assertEqual((3, [], []), (rc, adapter.pushes, adapter.writes))
                conflict = instructions[-1]
                self.assertEqual("timvisher_gh_sync_conflict", conflict["code"])
                for flag in ("--ours", "--theirs", "--merge"):
                    self.assertTrue(any(f"timvisher_gh pr {verb} {flag}" in s for s in conflict["suggestions"]))
                self.assertEqual("", out)
                self.assertIn("! pr", self.stderr)
                self.assertEqual("B", self.bases()["body"])

    def test_someone_elses_object_is_only_pulled(self):
        item, adapter = self.setup(self.BASE, {"title": "T", "body": "my edit"}, dict(self.BASE), mine=False)
        rc, _, instructions = self.run_engine("sync", item)
        self.assertEqual((0, []), (rc, adapter.pushes))
        self.assertEqual(["timvisher_gh_read_only"], [i["code"] for i in instructions])
        item, adapter = self.setup(None, {"title": "T", "body": "my edit"}, {"title": "T", "body": "theirs"}, mine=False)
        rc, _, instructions = self.run_engine("pull", item)
        self.assertEqual((0, [{"title": "T", "body": "theirs"}]), (rc, adapter.writes))
        self.assertIn("timvisher_gh_discarding_local_edits", [i["code"] for i in instructions])
        item, adapter = self.setup(None, dict(self.BASE), {"title": "T", "body": "newer"}, mine=False)
        rc, _, _ = self.run_engine("push", item)
        self.assertEqual((0, [], []), (rc, adapter.pushes, adapter.writes))

    def test_normalization_ignores_crlf_and_trailing_newlines(self):
        item, adapter = self.setup(self.BASE, {"title": "T\n", "body": "B\r\n\n"}, {"title": "T", "body": "B\n"})
        self.assertEqual((0, [], []), (self.run_engine("sync", item)[0], adapter.pushes, adapter.writes))
        self.assertEqual("x\ny", sync.normalize("x\r\ny\n\n"))

    def test_an_object_without_a_base_adopts_githubs_values(self):
        item, adapter = self.setup(None, {"title": "T", "body": "B"}, {"title": "T", "body": "B"})
        self.assertEqual(0, self.run_engine("sync", item)[0])
        self.assertEqual({"title": "T", "body": "B"}, self.bases())

    def test_the_stale_check_aborts_an_object_that_moved_after_the_fetch(self):
        item, adapter = self.setup(self.BASE, {"title": "T2", "body": "B"}, dict(self.BASE))

        def someone_edits(a):
            if a.fetches == 2:
                a.remote["body"] = "edited meanwhile"
        adapter.on_fetch = someone_edits
        rc, _, instructions = self.run_engine("push", item)
        self.assertEqual((1, []), (rc, adapter.pushes))
        self.assertEqual("timvisher_gh_stale", instructions[-1]["code"])

    def test_after_a_push_githubs_values_are_refetched_as_the_new_base(self):
        item, adapter = self.setup(self.BASE, {"title": "T2 ", "body": "B"}, dict(self.BASE))
        adapter.on_push = lambda a: a.remote.update(title="T2")
        self.assertEqual(0, self.run_engine("push", item)[0])
        self.assertEqual("T2", self.bases()["title"])
        self.assertEqual(3, adapter.fetches)

    def test_fetch_only_records_github(self):
        item, adapter = self.setup(self.BASE, {"title": "mine", "body": "B"}, {"title": "T", "body": "new"})
        self.assertEqual(0, self.run_engine("fetch", item)[0])
        self.assertEqual(([], [], self.BASE), (adapter.pushes, adapter.writes, self.bases()))
        remote = dict(self.state.db.execute("SELECT name, remote FROM fields WHERE object_id = 'PR_7'"))
        self.assertEqual('"new"', remote["body"])

    def test_ours_pushes_yours_or_for_pull_keeps_it_as_unpushed(self):
        item, adapter = self.setup(self.BASE, {"title": "T", "body": "mine"}, {"title": "T", "body": "theirs"})
        self.assertEqual(0, self.run_engine("sync", item, resolution="ours")[0])
        self.assertEqual(([{"body": "mine"}], "mine"), (adapter.pushes, self.bases()["body"]))
        item, adapter = self.setup(self.BASE, {"title": "T", "body": "mine"}, {"title": "T", "body": "theirs"})
        self.assertEqual(0, self.run_engine("pull", item, resolution="ours")[0])
        self.assertEqual(([], [], "theirs"), (adapter.pushes, adapter.writes, self.bases()["body"]))

    def test_theirs_overwrites_the_source(self):
        item, adapter = self.setup(self.BASE, {"title": "T", "body": "mine"}, {"title": "T", "body": "theirs"})
        self.assertEqual(0, self.run_engine("push", item, resolution="theirs")[0])
        self.assertEqual(([], {"title": "T", "body": "theirs"}, "theirs"),
                         (adapter.pushes, adapter.source, self.bases()["body"]))

    def test_theirs_on_several_fields_keeps_every_refreshed_value(self):
        item, adapter = self.setup(self.BASE, {"title": "T", "body": "mine"}, {"title": "T2", "body": "theirs"})
        self.assertEqual(0, self.run_engine("sync", item, resolution="theirs")[0])
        self.assertEqual({"title": "T2", "body": "theirs"}, adapter.source)
        item2, adapter2 = self.setup(None, dict(adapter.source), dict(adapter.remote))
        self.assertEqual((0, []), (self.run_engine("sync", item2)[0], adapter2.pushes))

    def test_an_interactive_ours_never_pushes_to_an_object_that_is_refused(self):
        item, adapter = self.setup(self.BASE, {"title": "T", "body": "mine"}, {"title": "T2", "body": "theirs"})
        rc, _, instructions = self.run_engine("push", item, ask=lambda plan: "ours")
        self.assertEqual((4, []), (rc, adapter.pushes))
        self.assertEqual("timvisher_gh_push_refused", instructions[-1]["code"])

    def test_a_stale_object_doesnt_hide_another_objects_decision(self):
        stale, stale_adapter = self.setup(self.BASE, {"title": "T2", "body": "B"}, dict(self.BASE))
        stale_adapter.on_fetch = lambda a: a.remote.update(body=f"moved {a.fetches}") if a.fetches == 2 else None
        with self.state.write() as db:
            store.register(db, id="PR_8", kind="pr", url=URL[:-1] + "8", owner="O", repo="R", number=8,
                           store_path="github.com/O/R/pull/8")
            for name, value in self.BASE.items():
                store.set_base(db, "PR_8", name, value, "t0")
        torn = sync.Item("PR_8", "pr", URL[:-1] + "8", Adapter({"title": "T", "body": "theirs"},
                                                               {"title": "T", "body": "mine"}))
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            rc = sync.Engine(self.state, "push", now="t1", rerun="timvisher_gh pr push").run([stale, torn])
        codes = [json.loads(line)["code"] for line in err.getvalue().splitlines() if line.startswith("{")]
        self.assertEqual(1, rc)
        self.assertIn("timvisher_gh_stale", codes)
        self.assertIn("timvisher_gh_sync_conflict", codes)

    def test_merge_applies_a_clean_merge(self):
        base = {"title": "T", "body": "one\ntwo\nthree"}
        item, adapter = self.setup(base, {"title": "T", "body": "ONE\ntwo\nthree"}, {"title": "T", "body": "one\ntwo\nTHREE"})
        self.assertEqual(0, self.run_engine("sync", item, resolution="merge")[0])
        self.assertEqual([{"body": "ONE\ntwo\nTHREE"}], adapter.pushes)
        self.assertEqual("ONE\ntwo\nTHREE", self.bases()["body"])

    def test_merge_leaves_conflict_markers_and_exits_3(self):
        item, adapter = self.setup(self.BASE, {"title": "T", "body": "mine"}, {"title": "T", "body": "theirs"})
        rc, _, instructions = self.run_engine("sync", item, resolution="merge")
        self.assertEqual((3, []), (rc, adapter.pushes))
        self.assertIn("<<<<<<<", adapter.source["body"])
        self.assertEqual("timvisher_gh_merge_conflict", instructions[-1]["code"])

    def test_ours_overrides_a_refusal(self):
        item, adapter = self.setup(self.BASE, dict(self.BASE), {"title": "T", "body": "B2"})
        self.assertEqual(0, self.run_engine("push", item, resolution="ours")[0])
        self.assertEqual([{"body": "B"}], adapter.pushes)

    def test_a_decision_and_another_fields_push_both_apply(self):
        item, adapter = self.setup(self.BASE, {"title": "T2", "body": "mine"}, {"title": "T", "body": "theirs"})
        self.assertEqual(0, self.run_engine("sync", item, resolution="ours")[0])
        self.assertEqual(sorted([("body", "mine"), ("title", "T2")]),
                         sorted(pair for push in adapter.pushes for pair in push.items()))

    def test_interactive_decisions_ask_and_a_skip_exits_3(self):
        for answer, expected in (("ours", 0), (None, 3)):
            item, adapter = self.setup(self.BASE, {"title": "T", "body": "mine"}, {"title": "T", "body": "theirs"})
            rc, out, _ = self.run_engine("sync", item, ask=lambda plan: answer)
            self.assertEqual(expected, rc, answer)
            self.assertIn("decision: changed here and on GitHub", self.stderr)

    def test_the_prompt_reads_an_answer(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual("theirs", sync.prompt(mock.Mock(item=mock.Mock(url=URL)), io.StringIO("t\n")))
            self.assertIsNone(sync.prompt(mock.Mock(item=mock.Mock(url=URL)), io.StringIO("s\n")))

    def test_interactive_needs_a_tty_and_no_agent(self):
        with mock.patch("sys.stdin") as stdin:
            stdin.isatty.return_value = True
            with mock.patch.dict(os.environ, {"TIMVISHER_AGENT": ""}):
                self.assertTrue(sync.interactive())
            self.assertFalse(sync.interactive())
            stdin.isatty.return_value = False
            with mock.patch.dict(os.environ, {"TIMVISHER_AGENT": ""}):
                self.assertFalse(sync.interactive())

    def test_plan_human_form(self):
        item, adapter = self.setup(self.BASE, {"title": "T2", "body": "mine"}, {"title": "T", "body": "theirs"})
        with mock.patch.dict(os.environ, {"TIMVISHER_AGENT": ""}):
            rc, out, _ = self.run_engine("sync", item, plan_only=True)
        self.assertEqual((3, [], []), (rc, adapter.pushes, adapter.writes))
        lines = out.splitlines()
        self.assertEqual(f"! pr      {URL}  decision: changed here and on GitHub", lines[0])
        self.assertIn("<<<<<<< yours", out)
        self.assertEqual("Plan: 0 to push, 0 to refresh, 1 decision, 0 unchanged.", lines[-1])

    def test_plan_counts_and_markers(self):
        plans = [sync.Plan(sync.Item(f"I{n}", "comment", f"{URL}#issuecomment-{n}", Adapter({}, {})), action,
                           {"body": action}, {}, {}, {})
                 for n, action in enumerate(("push", "refresh", "unchanged", "unchanged"))]
        text = sync.render(plans)
        self.assertIn(f"~ comment {URL}#issuecomment-0  update body", text)
        self.assertIn(f"< comment {URL}#issuecomment-1  refresh body (changed on GitHub)", text)
        self.assertTrue(text.endswith("Plan: 1 to push, 1 to refresh, 0 decisions, 2 unchanged.\n"))

    def test_plan_agent_form_is_also_an_aictl_instruction(self):
        item, adapter = self.setup(self.BASE, {"title": "T2", "body": "B"}, dict(self.BASE))
        rc, out, instructions = self.run_engine("push", item, plan_only=True)
        self.assertEqual((0, []), (rc, adapter.pushes))
        plan = instructions[-1]
        self.assertEqual(("timvisher_gh_plan", [{"url": URL, "action": "push", "fields": ["title"]}]),
                         (plan["code"], plan["data"]["objects"]))
        self.assertIn("~ pr", out)


if __name__ == "__main__":
    unittest.main()
