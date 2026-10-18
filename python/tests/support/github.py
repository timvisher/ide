import json
import pathlib
import sys

FAKE_GH = pathlib.Path(__file__).resolve().with_name("fake_gh.py")


class FakeGitHub:
    def __init__(self, root, viewer="testuser"):
        self.root = pathlib.Path(root)
        self.state_path = self.root / "gh-state.json"
        self.log_path = self.root / "gh-calls.jsonl"
        self.bin = self.root / "bin"
        self.bin.mkdir(parents=True, exist_ok=True)
        self.log_path.touch()
        shim = self.bin / "gh"
        shim.write_text(f"#!/bin/sh\nexec '{sys.executable}' '{FAKE_GH}' \"$@\"\n")
        shim.chmod(0o755)
        self._write({
            "viewer": viewer, "next_id": 1000, "repos": {}, "pulls": {}, "issues": {},
            "issue_comments": {}, "review_comments": {}, "reactions": {}, "threads": {},
            "deleted": [], "responses": [],
        })

    def env(self):
        return {"FAKE_GH_STATE": str(self.state_path), "FAKE_GH_LOG": str(self.log_path)}

    @property
    def state(self):
        return json.loads(self.state_path.read_text())

    def _write(self, state):
        self.state_path.write_text(json.dumps(state, indent=2))

    def _update(self, change):
        state = self.state
        result = change(state)
        self._write(state)
        return result

    @property
    def calls(self):
        return [json.loads(line) for line in self.log_path.read_text().splitlines()]

    def add_repo(self, repo, default_branch="main", fork=False, source=None, archived=False):
        def change(state):
            state["repos"][repo] = {"default_branch": default_branch, "fork": fork,
                                    "source": source and {"full_name": source}, "archived": archived}
        self._update(change)

    def add_pull(self, repo, number, *, head, title="", body="", base="main", draft=False,
                 state="open", merged=False, head_owner=None):
        def change(s):
            s["pulls"].setdefault(repo, {})[str(number)] = {
                "number": number, "title": title, "body": body, "head": head,
                "head_owner": head_owner or repo.split("/")[0], "base": base, "draft": draft,
                "state": state, "merged": merged}
        self._update(change)

    def add_issue(self, repo, number, *, title="", body="", state="open"):
        def change(s):
            s["issues"].setdefault(repo, {})[str(number)] = {
                "number": number, "title": title, "body": body, "state": state}
        self._update(change)

    def add_issue_comment(self, repo, number, body, *, user=None):
        def change(s):
            s["next_id"] += 1
            comment_id = s["next_id"]
            s["issue_comments"][str(comment_id)] = {
                "id": comment_id, "node_id": f"IC_{comment_id}", "repo": repo, "issue_number": number,
                "body": body, "user": user or s["viewer"],
                "html_url": f"https://github.com/{repo}/pull/{number}#issuecomment-{comment_id}"}
            return comment_id
        return self._update(change)

    def add_review_comment(self, repo, number, body, *, path="README.md", line=1, side="RIGHT",
                           reply_to=None, user=None):
        def change(s):
            s["next_id"] += 1
            comment_id = s["next_id"]
            comment = {"id": comment_id, "node_id": f"PRRC_{comment_id}", "repo": repo, "pull_number": number,
                       "body": body, "user": user or s["viewer"],
                       "html_url": f"https://github.com/{repo}/pull/{number}#discussion_r{comment_id}"}
            if reply_to is None:
                comment.update(path=path, line=line, start_line=None, side=side, commit_id=None)
                s["threads"][f"PRRT_{comment_id}"] = {"repo": repo, "pull_number": number,
                                                      "comments": [comment_id], "resolved": False}
            else:
                comment["in_reply_to_id"] = reply_to
                next(t for t in s["threads"].values() if reply_to in t["comments"])["comments"].append(comment_id)
            s["review_comments"][str(comment_id)] = comment
            return comment_id
        return self._update(change)

    def add_reaction(self, kind, comment_id, content, *, user):
        def change(s):
            s["next_id"] += 1
            s["reactions"].setdefault(f"{kind}:{comment_id}", []).append(
                {"id": s["next_id"], "content": content, "user": user})
            return s["next_id"]
        return self._update(change)

    def thread_of(self, comment_id):
        return next(node_id for node_id, t in self.state["threads"].items() if comment_id in t["comments"])

    def respond(self, argv, stdout="", stderr="", status=0):
        def change(s):
            s["responses"].append({"argv": list(argv), "stdout": stdout, "stderr": stderr, "status": status})
        self._update(change)
