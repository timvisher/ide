import dataclasses
import json
import os
import subprocess
import sys
import tempfile

from timvisher import aictl
from timvisher.gh import store
from timvisher.gh.errors import ERROR

DECISION = 3
REFUSED = 4

VERBS = ("fetch", "pull", "push", "sync", "edit")
PUSHING = ("push", "sync", "edit")
PULLING = ("pull", "sync")
MARKERS = {"create": "+", "push": "~", "refresh": "<", "decision": "!", "delete": "-", "refused": "<",
           "unpushed": "~", "readonly": "~", "base": " ", "unchanged": " "}


@dataclasses.dataclass
class Item:
    object_id: str
    kind: str
    url: str
    adapter: object
    mine: bool = True


@dataclasses.dataclass
class Plan:
    item: Item
    action: str
    fields: dict
    base: dict
    source: dict
    remote: dict
    detail: str = ""


def normalize(value):
    if isinstance(value, str):
        return value.replace("\r\n", "\n").rstrip("\n")
    return value


def interactive():
    return sys.stdin.isatty() and not os.environ.get("TIMVISHER_AGENT")


def classify(verb, item, base, source, remote):
    if source is None:
        source = dict(base)
    outcome = {}
    for name in item.adapter.managed:
        s_changed = normalize(source.get(name)) != normalize(base.get(name))
        g_changed = normalize(remote.get(name)) != normalize(base.get(name))
        if not item.mine:
            outcome[name] = "refresh" if g_changed else ("readonly" if s_changed else "unchanged")
        elif not s_changed and not g_changed:
            outcome[name] = "unchanged"
        elif s_changed and not g_changed:
            outcome[name] = "push" if verb in PUSHING else "unpushed"
        elif not s_changed:
            outcome[name] = "refresh" if verb in PULLING else "refused"
        elif normalize(source.get(name)) == normalize(remote.get(name)):
            outcome[name] = "base"
        else:
            outcome[name] = "decision"
    if not item.mine and verb == "push":
        outcome = {name: "readonly" if result == "readonly" else "unchanged" for name, result in outcome.items()}
    for action in ("decision", "refused", "push", "refresh", "unpushed", "readonly", "base"):
        fields = [name for name, result in outcome.items() if result == action]
        if fields:
            return action, outcome
    return "unchanged", outcome


def _three_way(name, base, source, remote):
    with tempfile.TemporaryDirectory() as tmp:
        paths = []
        for label, value in (("yours", source), ("base", base), ("GitHub", remote)):
            path = os.path.join(tmp, label)
            with open(path, "w", encoding="utf-8") as stream:
                stream.write(f"{normalize(value) or ''}\n" if isinstance(value, str) or value is None
                             else f"{json.dumps(value)}\n")
            paths.append(path)
        done = subprocess.run(["git", "merge-file", "-p", "--diff3", "-L", "yours", "-L", "base", "-L", "GitHub",
                               *paths], stdout=subprocess.PIPE, text=True)
        return name, done.returncode, done.stdout


def merge_field(base, source, remote):
    _, conflicts, text = _three_way("", base, source, remote)
    return conflicts, text.rstrip("\n")


def _describe(plan):
    fields = ", ".join(plan.fields)
    return {
        "push": f"update {fields}",
        "refresh": f"refresh {fields} (changed on GitHub)",
        "decision": "decision: changed here and on GitHub",
        "refused": f"pull first: {fields} changed on GitHub",
        "unpushed": f"unpushed {fields}; push to send",
        "readonly": f"local edits to someone else's {plan.item.kind} aren't pushed ({fields})",
        "base": f"record {fields} as agreed",
        "unchanged": "unchanged",
    }.get(plan.action, plan.action) + (f" {plan.detail}" if plan.detail else "")


def render(plans):
    width = max((len(p.item.url) for p in plans), default=0)
    lines = []
    for plan in plans:
        if plan.action == "unchanged":
            continue
        lines.append(f"{MARKERS[plan.action]} {plan.item.kind:<7} {plan.item.url:<{width}}  {_describe(plan)}")
        if plan.action == "decision":
            for name in plan.fields:
                _, _, diff = _three_way(name, plan.base.get(name), plan.source.get(name), plan.remote.get(name))
                lines += [f"    {name}:"] + [f"      {line}" for line in diff.rstrip("\n").splitlines()]
    counts = {action: sum(p.action == action for p in plans) for action in MARKERS}
    parts = [f"{counts['create']} to create"] if counts["create"] else []
    parts += [f"{counts['push']} to push", f"{counts['refresh']} to refresh",
              f"{counts['decision']} decision{'s' if counts['decision'] != 1 else ''}"]
    for action, label in (("refused", "to pull first"), ("unpushed", "unpushed"), ("readonly", "read-only"),
                          ("base", "agreed"), ("delete", "to delete")):
        if counts[action]:
            parts.append(f"{counts[action]} {label}")
    parts.append(f"{counts['unchanged']} unchanged")
    lines.append(f"Plan: {', '.join(parts)}.")
    return "\n".join(lines) + "\n"


def emit_plan(plans, stream=None):
    stream = stream or sys.stdout
    text = render(plans)
    stream.write(text)
    if os.environ.get("TIMVISHER_AGENT"):
        aictl.info(code="timvisher_gh_plan", message=text.splitlines()[-1],
                   data={"objects": [{"url": p.item.url, "action": p.action, "fields": list(p.fields)}
                                     for p in plans]})


def _conflict(plans, rerun):
    urls = [p.item.url for p in plans]
    aictl.error(code="timvisher_gh_sync_conflict",
         message=f"{len(urls)} object(s) changed both here and on GitHub: {', '.join(urls)}.",
         reason="Nothing was applied to them, and their files are untouched.",
         suggestions=[f"{rerun} --ours   (push yours over GitHub's change)",
                      f"{rerun} --theirs (overwrite your file from GitHub)",
                      f"{rerun} --merge  (git merge-file, then apply if it merges cleanly)"])


class Engine:
    def __init__(self, state, verb, *, now, rerun, resolution=None, plan_only=False, ask=None, out=None):
        assert verb in VERBS
        self.state = state
        self.verb = verb
        self.now = now
        self.rerun = rerun
        self.resolution = resolution
        self.plan_only = plan_only
        self.ask = ask
        self.out = out or sys.stdout
        self.failed = []

    def _base(self, item, remote):
        base = store.bases(self.state.db, item.object_id)
        missing = [name for name in item.adapter.managed if name not in base]
        for name in missing:
            base[name] = remote.get(name)
            store.set_base(self.state.db, item.object_id, name, remote.get(name), self.now)
        return base

    def _fetch(self, item):
        remote = item.adapter.fetch(item)
        for name, value in remote.items():
            store.set_remote(self.state.db, item.object_id, name, value, self.now)
        self.state.touch(item.object_id)
        return remote

    def plan(self, item):
        remote = self._fetch(item)
        base = self._base(item, remote)
        source = item.adapter.read_source(item)
        action, outcome = classify(self.verb, item, base, source, remote)
        fields = {name: result for name, result in outcome.items() if result != "unchanged"}
        return Plan(item, action, fields, base, source if source is not None else dict(base), remote)

    def _record_base(self, item, values):
        for name, value in values.items():
            store.set_base(self.state.db, item.object_id, name, value, self.now)

    def _write(self, plan, values):
        plan.source.update(values)
        plan.item.adapter.write_source(plan.item, dict(plan.source))

    def _refresh(self, plan, names):
        values = {name: plan.remote[name] for name in names}
        self._write(plan, values)
        self._record_base(plan.item, values)

    def _push(self, plan, names):
        item = plan.item
        current = item.adapter.fetch(item)
        if any(normalize(current.get(n)) != normalize(plan.remote.get(n)) for n in item.adapter.managed):
            aictl.error(code="timvisher_gh_stale", message=f"{item.url} changed on GitHub during this run; "
                        "nothing was pushed to it.", suggestions=[f"Rerun: {self.rerun}"])
            self.failed.append(item.url)
            return
        item.adapter.push(item, {name: plan.source[name] for name in names})
        after = self._fetch(item)
        self._record_base(item, {name: after.get(name) for name in names})
        plan.remote.update(after)

    def _resolve(self, plan, names):
        choice = self.resolution
        if choice is None and self.ask is not None:
            emit_plan([plan], sys.stderr)
            choice = self.ask(plan)
        match choice:
            case "ours":
                if self.verb in PUSHING:
                    self._push(plan, names)
                else:
                    self._record_base(plan.item, {name: plan.remote[name] for name in names})
                return "done"
            case "theirs":
                self._refresh(plan, names)
                return "done"
            case "merge":
                merged, conflicted = {}, False
                for name in names:
                    conflicts, text = merge_field(plan.base.get(name), plan.source.get(name), plan.remote.get(name))
                    merged[name] = text
                    conflicted = conflicted or 0 < conflicts
                self._write(plan, merged)
                if conflicted:
                    aictl.error(code="timvisher_gh_merge_conflict",
                                message=f"Merging {plan.item.url} left conflict markers in its source.",
                                suggestions=["Resolve the markers in the file, then rerun"])
                    return "conflict"
                self._record_base(plan.item, {name: plan.remote[name] for name in names})
                outcome = self._apply(self.plan(plan.item))
                return "replanned" if outcome == "done" else outcome
        return "undecided"

    def _report(self, plan, names, kind):
        if kind == "unpushed":
            aictl.info(code="timvisher_gh_unpushed", message=f"{plan.item.url} has unpushed {', '.join(names)}.",
                       suggestions=[f"Send it with {self.rerun.replace(' pull', ' push', 1)}"])
        else:
            aictl.notice(code="timvisher_gh_read_only",
                         message=f"Your local edits to someone else's {plan.item.kind} {plan.item.url} "
                                 f"({', '.join(names)}) aren't pushed.")

    def _apply(self, plan):
        names = lambda action: [n for n, r in plan.fields.items() if r == action]
        if names("refused") and self.resolution not in ("ours", "theirs"):
            return "refused"
        if names("decision"):
            outcome = self._resolve(plan, names("decision"))
            if outcome != "done":
                return "done" if outcome == "replanned" else outcome
        if names("refused"):
            self._resolve(plan, names("refused"))
        if names("base"):
            self._record_base(plan.item, {name: plan.remote[name] for name in names("base")})
        if names("refresh") and self.verb in PULLING:
            if not plan.item.mine:
                lost = [n for n in names("refresh")
                        if normalize(plan.source.get(n)) != normalize(plan.base.get(n))]
                if lost:
                    aictl.notice(code="timvisher_gh_discarding_local_edits",
                                 message=f"Discarding your local edits to someone else's {plan.item.kind} "
                                         f"{plan.item.url} ({', '.join(lost)}); it is read-only.")
            self._refresh(plan, names("refresh"))
        if names("push") and self.verb in PUSHING:
            self._push(plan, names("push"))
        for kind in ("unpushed", "readonly"):
            if names(kind):
                self._report(plan, names(kind), kind)
        return "done"

    def run(self, items):
        outcomes = []
        with self.state.write():
            if self.verb == "fetch":
                for item in items:
                    self._fetch(item)
                return 0
            plans = [self.plan(item) for item in items]
            if self.plan_only:
                emit_plan(plans, self.out)
                return DECISION if any(p.action == "decision" for p in plans) else 0
            for plan in plans:
                if plan.action == "decision" and self.resolution is None and self.ask is None:
                    outcomes.append((plan, "undecided"))
                else:
                    outcomes.append((plan, self._apply(plan)))
        undecided = [plan for plan, outcome in outcomes if outcome == "undecided"]
        if undecided:
            emit_plan(undecided, sys.stderr)
            _conflict(undecided, self.rerun)
        refused = [plan.item.url for plan, outcome in outcomes if outcome == "refused"]
        if refused:
            aictl.error(code="timvisher_gh_push_refused",
                        message=f"GitHub has changes to pull first: {', '.join(refused)}.",
                        reason="Pushing would overwrite them; nothing was pushed to those objects.",
                        suggestions=[f"{self.rerun.replace(' push', ' pull', 1)} first, then rerun this",
                                     f"Or {self.rerun} --ours to overwrite them"])
        if self.failed:
            return ERROR
        if undecided or any(outcome == "conflict" for _, outcome in outcomes):
            return DECISION
        return REFUSED if refused else 0


def prompt(plan, stream=None):
    stream = stream or sys.stdin
    while True:
        sys.stderr.write(f"{plan.item.url}: [o]urs, [t]heirs, [m]erge or [s]kip? ")
        sys.stderr.flush()
        answer = stream.readline().strip().lower()
        for choice in ("ours", "theirs", "merge", "skip"):
            if answer and choice.startswith(answer):
                return None if choice == "skip" else choice
        if not answer:
            return None
