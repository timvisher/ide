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
            "issue_comments": {}, "review_comments": {}, "reactions": {}, "threads": {}, "reviews": {},
            "deleted": [], "responses": [], "now": "2026-10-10T10:00:00Z",
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

    def add_repo(self, repo, default_branch="main", fork=False, source=None, archived=False,
                 merge=True, squash=False, rebase=False):
        def change(state):
            state["repos"][repo] = {"default_branch": default_branch, "fork": fork,
                                    "source": source and {"full_name": source}, "archived": archived,
                                    "allow_merge_commit": merge, "allow_squash_merge": squash,
                                    "allow_rebase_merge": rebase}
        self._update(change)

    def update_pull(self, repo, number, **changes):
        self._update(lambda s: s["pulls"][repo][str(number)].update(changes))

    def set_now(self, when):
        self._update(lambda s: s.update(now=when))

    def add_pull(self, repo, number, *, head, title="", body="", base="main", draft=False,
                 state="open", merged=False, head_owner=None, author=None, head_sha="0" * 40,
                 created_at=None, merged_at=None, merge_commit_sha=None):
        def change(s):
            s["pulls"].setdefault(repo, {})[str(number)] = {
                "number": number, "title": title, "body": body, "head": head,
                "head_owner": head_owner or repo.split("/")[0], "base": base, "draft": draft,
                "state": state, "merged": merged, "author": author or s["viewer"],
                "created_at": created_at or s["now"], "updated_at": created_at or s["now"],
                "head_sha": head_sha, "merged_at": merged_at, "merge_commit_sha": merge_commit_sha}
        self._update(change)

    def add_issue(self, repo, number, *, title="", body="", state="open", author=None, closed_at=None):
        def change(s):
            s["issues"].setdefault(repo, {})[str(number)] = {
                "number": number, "title": title, "body": body, "state": state, "author": author or s["viewer"],
                "created_at": s["now"], "updated_at": s["now"], "closed_at": closed_at}
        self._update(change)

    def add_issue_comment(self, repo, number, body, *, user=None):
        def change(s):
            s["next_id"] += 1
            comment_id = s["next_id"]
            s["issue_comments"][str(comment_id)] = {
                "id": comment_id, "node_id": f"IC_{comment_id}", "repo": repo, "issue_number": number,
                "body": body, "user": user or s["viewer"], "created_at": s["now"], "updated_at": s["now"],
                "html_url": f"https://github.com/{repo}/{'pull' if str(number) in s['pulls'].get(repo, {}) else 'issues'}/{number}#issuecomment-{comment_id}"}
            return comment_id
        return self._update(change)

    def add_review_comment(self, repo, number, body, *, path="README.md", line=1, side="RIGHT",
                           reply_to=None, user=None):
        def change(s):
            s["next_id"] += 1
            comment_id = s["next_id"]
            comment = {"id": comment_id, "node_id": f"PRRC_{comment_id}", "repo": repo, "pull_number": number,
                       "body": body, "user": user or s["viewer"], "created_at": s["now"], "updated_at": s["now"],
                       "pull_request_review_id": None,
                       "html_url": f"https://github.com/{repo}/pull/{number}#discussion_r{comment_id}"}
            if reply_to is None:
                comment.update(path=path, line=line, start_line=None, side=side, commit_id="0" * 40)
                s["threads"][f"PRRT_{comment_id}"] = {"repo": repo, "pull_number": number,
                                                      "comments": [comment_id], "resolved": False}
            else:
                root = s["review_comments"][str(reply_to)]
                comment.update({key: root[key] for key in ("path", "line", "start_line", "side", "commit_id")})
                comment["in_reply_to_id"] = reply_to
                next(t for t in s["threads"].values() if reply_to in t["comments"])["comments"].append(comment_id)
            s["review_comments"][str(comment_id)] = comment
            return comment_id
        return self._update(change)

    def add_review(self, repo, number, *, user, state="COMMENTED", body=""):
        def change(s):
            s["next_id"] += 1
            review_id = s["next_id"]
            s["reviews"][str(review_id)] = {
                "id": review_id, "node_id": f"PRR_{review_id}", "repo": repo, "pull_number": number,
                "user": user, "state": state, "body": body, "submitted_at": s["now"],
                "html_url": f"https://github.com/{repo}/pull/{number}#pullrequestreview-{review_id}"}
            return review_id
        return self._update(change)

    def set_outdated(self, thread_id, outdated=True):
        self._update(lambda s: s["threads"][thread_id].update(outdated=outdated))

    def add_reaction(self, kind, comment_id, content, *, user):
        def change(s):
            s["next_id"] += 1
            s["reactions"].setdefault(f"{kind}:{comment_id}", []).append(
                {"id": s["next_id"], "content": content, "user": user})
            return s["next_id"]
        return self._update(change)

    def thread_of(self, comment_id):
        return next(node_id for node_id, t in self.state["threads"].items() if comment_id in t["comments"])

    def respond(self, argv, stdout="", stderr="", status=0, once=False, aictl=""):
        def change(s):
            s["responses"].append({"argv": list(argv), "stdout": stdout, "stderr": stderr, "status": status,
                                   "once": once, "aictl": aictl})
        self._update(change)
