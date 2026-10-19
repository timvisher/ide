import json
import os
import re
import subprocess
import sys

STATUS_TEXT = {200: "OK", 201: "Created", 204: "No Content", 404: "Not Found", 422: "Unprocessable Entity"}
REACTIONS = ("+1", "-1", "laugh", "confused", "heart", "hooray", "rocket", "eyes")
PER_PAGE = 30


class Reply(Exception):
    def __init__(self, status, body=None):
        super().__init__(status)
        self.status = status
        self.body = body


def not_found():
    return Reply(404, {"message": "Not Found"})


def invalid(message):
    return Reply(422, {"message": f"Validation Failed: {message}"})


def require(fields, *names):
    missing = [name for name in names if fields.get(name) in (None, "")]
    if missing:
        raise invalid(", ".join(f"{name} is missing" for name in missing))


def load():
    with open(os.environ["FAKE_GH_STATE"], encoding="utf-8") as stream:
        return json.load(stream)


def save(state):
    path = os.environ["FAKE_GH_STATE"]
    with open(path + ".tmp", "w", encoding="utf-8") as stream:
        json.dump(state, stream, indent=2)
    os.replace(path + ".tmp", path)


def record(entry):
    with open(os.environ["FAKE_GH_LOG"], "a", encoding="utf-8") as stream:
        stream.write(json.dumps(entry) + "\n")


def new_id(state):
    state["next_id"] += 1
    return state["next_id"]


def typed(value):
    if value in ("true", "false"):
        return value == "true"
    if value == "null":
        return None
    if re.fullmatch(r"-?\d+", value):
        return int(value)
    if value.startswith("@"):
        source = value[1:]
        if source == "-":
            return sys.stdin.read()
        with open(source, encoding="utf-8") as stream:
            return stream.read()
    return value


def parse_api(args):
    request = {"method": None, "path": None, "fields": {}, "jq": None, "include": False,
               "silent": False, "input": None, "hostname": None, "paginate": False}
    i = 0
    while i < len(args):
        arg = args[i]
        value = args[i + 1] if i + 1 < len(args) else None
        if arg in ("-X", "--method"):
            request["method"] = value.upper()
            i += 2
        elif arg in ("-f", "--raw-field", "-F", "--field"):
            key, _, raw = value.partition("=")
            request["fields"][key] = raw if arg in ("-f", "--raw-field") else typed(raw)
            i += 2
        elif arg in ("-q", "--jq"):
            request["jq"] = value
            i += 2
        elif arg == "--input":
            request["input"] = value
            i += 2
        elif arg == "--hostname":
            request["hostname"] = value
            i += 2
        elif arg in ("-H", "--header", "--cache", "-p", "--preview", "-t", "--template"):
            i += 2
        elif arg in ("-i", "--include"):
            request["include"] = True
            i += 1
        elif arg == "--silent":
            request["silent"] = True
            i += 1
        elif arg == "--paginate":
            request["paginate"] = True
            i += 1
        elif arg in ("--slurp", "--verbose", "--allow-escape-sequences"):
            i += 1
        else:
            request["path"] = arg
            i += 1
    if request["input"] is not None:
        if request["input"] == "-":
            body = sys.stdin.read()
        else:
            with open(request["input"], encoding="utf-8") as stream:
                body = stream.read()
        payload = json.loads(body) if body.strip() else {}
        if request["path"] == "graphql":
            payload = {"query": payload.get("query", ""), **payload.get("variables", {})}
        request["fields"].update(payload)
    if request["method"] is None:
        request["method"] = "POST" if request["fields"] and request["path"] != "graphql" else "GET"
    if request["path"] == "graphql":
        request["method"] = "POST"
    path = request["path"] or ""
    request["path"], _, query = path.lstrip("/").partition("?")
    request["query"] = dict(pair.partition("=")[::2] for pair in query.split("&") if pair)
    if request["method"] == "GET":
        request["query"].update({key: str(value) for key, value in request["fields"].items()})
        request["fields"] = {}
    return request


def user(login):
    return {"login": login, "type": "User"}


def comment_view(state, kind, comment):
    view = {key: value for key, value in comment.items() if key not in ("repo", "issue_number", "pull_number")}
    api = f"https://api.github.com/repos/{comment['repo']}"
    if kind == "issue_comment":
        view["issue_url"] = f"{api}/issues/{comment['issue_number']}"
    else:
        view["pull_request_url"] = f"{api}/pulls/{comment['pull_number']}"
    view["user"] = user(comment["user"])
    view["reactions"] = reaction_summary(state, kind, comment["id"])
    return view


def reaction_summary(state, kind, comment_id):
    summary = {"total_count": 0, **dict.fromkeys(REACTIONS, 0)}
    for reaction in state["reactions"].get(f"{kind}:{comment_id}", []):
        summary[reaction["content"]] += 1
        summary["total_count"] += 1
    return summary


def page(request, items):
    if request["paginate"]:
        return items
    size = int(request["query"].get("per_page", PER_PAGE))
    number = int(request["query"].get("page", 1))
    return items[(number - 1) * size: number * size]


def find_comment(state, kind, repo, comment_id):
    table = state["issue_comments" if kind == "issue_comment" else "review_comments"]
    comment = table.get(str(comment_id))
    if comment is None or comment["repo"] != repo:
        raise not_found()
    return comment


def pull(state, repo, number):
    found = state["pulls"].get(repo, {}).get(str(number))
    if found is None:
        raise not_found()
    return found


def issue(state, repo, number):
    found = state["issues"].get(repo, {}).get(str(number))
    if found is None:
        raise not_found()
    return found


def next_number(state, repo):
    used = [int(n) for table in ("pulls", "issues") for n in state[table].get(repo, {})]
    return max(used, default=0) + 1


def thread_of(state, comment_id):
    for node_id, thread in state["threads"].items():
        if comment_id in thread["comments"]:
            return node_id
    return None


def canonical(state, repo):
    known = set(state["repos"]) | set(state["pulls"]) | set(state["issues"])
    return next((name for name in known if name.lower() == repo.lower()), repo)


def rest(state, request):
    method, path, fields = request["method"], request["path"], request["fields"]
    parts = path.split("/")

    if path == "user":
        return 200, user(state["viewer"])

    if len(parts) < 3 or parts[0] != "repos":
        raise not_found()
    repo = canonical(state, f"{parts[1]}/{parts[2]}")
    rest_parts = parts[3:]

    match method, rest_parts:
        case "GET", []:
            if repo not in state["repos"]:
                raise not_found()
            return 200, {"full_name": repo, **state["repos"][repo]}

        case "GET", ["pulls"]:
            head = request["query"].get("head")
            wanted = request["query"].get("state", "open")
            pulls = list(state["pulls"].get(repo, {}).values())
            if head:
                pulls = [p for p in pulls if f"{p['head_owner']}:{p['head']}" == head]
            if wanted != "all":
                pulls = [p for p in pulls if p["state"] == wanted]
            return 200, page(request, [pull_view(repo, p, listed=True) for p in pulls])
        case "POST", ["pulls"]:
            require(fields, "head", "base")
            number = next_number(state, repo)
            created = {"number": number, "title": fields.get("title", ""), "body": fields.get("body", ""),
                       "author": state["viewer"], "created_at": state["now"], "updated_at": state["now"],
                       "head_sha": "0" * 40, "merged_at": None, "merge_commit_sha": None,
                       "head": fields["head"].split(":")[-1],
                       "head_owner": fields["head"].split(":")[0] if ":" in fields["head"] else repo.split("/")[0],
                       "base": fields["base"],
                       "draft": bool(fields.get("draft", False)), "state": "open", "merged": False}
            state["pulls"].setdefault(repo, {})[str(number)] = created
            return 201, pull_view(repo, created)
        case "GET", ["pulls", number]:
            return 200, pull_view(repo, pull(state, repo, number))
        case "PATCH", ["pulls", number]:
            found = pull(state, repo, number)
            for key in ("title", "body", "base", "state"):
                if key in fields:
                    found[key] = fields[key]
            found["updated_at"] = state["now"]
            return 200, pull_view(repo, found)

        case "POST", ["issues"]:
            require(fields, "title")
            number = next_number(state, repo)
            created = {"number": number, "title": fields.get("title", ""), "body": fields.get("body", ""),
                       "state": "open", "author": state["viewer"], "created_at": state["now"],
                       "updated_at": state["now"], "closed_at": None}
            state["issues"].setdefault(repo, {})[str(number)] = created
            return 201, issue_view(repo, created)
        case "GET", ["issues", number] if number.isdigit():
            return 200, issue_view(repo, issue(state, repo, number))
        case "PATCH", ["issues", number] if number.isdigit():
            found = issue(state, repo, number)
            for key in ("title", "body", "state"):
                if key in fields:
                    found[key] = fields[key]
            return 200, issue_view(repo, found)

        case "GET", ["issues", number, "comments"]:
            return 200, page(request, [comment_view(state, "issue_comment", c) for c in state["issue_comments"].values()
                                       if c["repo"] == repo and c["issue_number"] == int(number)])
        case "POST", ["issues", number, "comments"]:
            if str(number) in state["pulls"].get(repo, {}):
                kind = "pull"
            elif str(number) in state["issues"].get(repo, {}):
                kind = "issues"
            else:
                raise not_found()
            require(fields, "body")
            comment_id = new_id(state)
            created = {"id": comment_id, "node_id": f"IC_{comment_id}", "repo": repo, "issue_number": int(number),
                       "body": fields["body"], "user": state["viewer"], "created_at": state["now"],
                       "updated_at": state["now"],
                       "html_url": f"https://github.com/{repo}/{kind}/{number}#issuecomment-{comment_id}"}
            state["issue_comments"][str(comment_id)] = created
            return 201, comment_view(state, "issue_comment", created)
        case "GET", ["issues", "comments", comment_id]:
            return 200, comment_view(state, "issue_comment", find_comment(state, "issue_comment", repo, comment_id))
        case "PATCH", ["issues", "comments", comment_id]:
            found = find_comment(state, "issue_comment", repo, comment_id)
            found["body"] = fields.get("body", found["body"])
            return 200, comment_view(state, "issue_comment", found)
        case "DELETE", ["issues", "comments", comment_id]:
            find_comment(state, "issue_comment", repo, comment_id)
            del state["issue_comments"][str(comment_id)]
            state["deleted"].append(f"issue_comment:{comment_id}")
            return 204, None

        case "GET", ["pulls", number, "comments"]:
            return 200, page(request, [comment_view(state, "review_comment", c) for c in state["review_comments"].values()
                                       if c["repo"] == repo and c["pull_number"] == int(number)])
        case "POST", ["pulls", number, "comments"]:
            pull(state, repo, number)
            reply_to = fields.get("in_reply_to")
            return 201, add_review_comment(state, repo, int(number), fields, reply_to)
        case "POST", ["pulls", number, "comments", comment_id, "replies"]:
            pull(state, repo, number)
            find_comment(state, "review_comment", repo, comment_id)
            return 201, add_review_comment(state, repo, int(number), fields, int(comment_id))
        case "GET", ["pulls", number, "reviews"]:
            pull(state, repo, number)
            return 200, page(request, [review_view(r) for r in state["reviews"].values()
                                       if r["repo"] == repo and r["pull_number"] == int(number)])
        case "GET", ["pulls", number, "reviews", review_id]:
            found = state["reviews"].get(review_id)
            if found is None or found["repo"] != repo or found["pull_number"] != int(number):
                raise not_found()
            return 200, review_view(found)

        case "GET", ["pulls", "comments", comment_id]:
            return 200, comment_view(state, "review_comment", find_comment(state, "review_comment", repo, comment_id))
        case "PATCH", ["pulls", "comments", comment_id]:
            found = find_comment(state, "review_comment", repo, comment_id)
            found["body"] = fields.get("body", found["body"])
            return 200, comment_view(state, "review_comment", found)
        case "DELETE", ["pulls", "comments", comment_id]:
            find_comment(state, "review_comment", repo, comment_id)
            del state["review_comments"][str(comment_id)]
            for thread in state["threads"].values():
                if int(comment_id) in thread["comments"]:
                    thread["comments"].remove(int(comment_id))
            state["deleted"].append(f"review_comment:{comment_id}")
            return 204, None

        case _, [("issues" | "pulls") as table, "comments", comment_id, "reactions", *rid]:
            kind = "issue_comment" if table == "issues" else "review_comment"
            find_comment(state, kind, repo, comment_id)
            reactions = state["reactions"].setdefault(f"{kind}:{comment_id}", [])
            if method == "GET" and not rid:
                return 200, page(request, [{"id": r["id"], "content": r["content"], "user": user(r["user"])}
                                           for r in reactions])
            if method == "POST" and not rid:
                if fields.get("content") not in REACTIONS:
                    raise invalid(f"content must be one of {', '.join(REACTIONS)}")
                for existing in reactions:
                    if existing["content"] == fields["content"] and existing["user"] == state["viewer"]:
                        return 200, {"id": existing["id"], "content": existing["content"], "user": user(existing["user"])}
                created = {"id": new_id(state), "content": fields["content"], "user": state["viewer"]}
                reactions.append(created)
                return 201, {"id": created["id"], "content": created["content"], "user": user(created["user"])}
            if method == "DELETE" and len(rid) == 1:
                kept = [r for r in reactions if str(r["id"]) != rid[0]]
                if len(kept) == len(reactions):
                    raise not_found()
                reactions[:] = kept
                return 204, None
    raise not_found()


def add_review_comment(state, repo, number, fields, reply_to):
    require(fields, "body")
    if reply_to is None:
        require(fields, "commit_id", "path")
        if fields.get("subject_type") != "file":
            require(fields, "line")
    comment_id = new_id(state)
    created = {"id": comment_id, "node_id": f"PRRC_{comment_id}", "repo": repo, "pull_number": number,
               "body": fields.get("body", ""), "user": state["viewer"], "created_at": state["now"],
               "updated_at": state["now"], "pull_request_review_id": None,
               "html_url": f"https://github.com/{repo}/pull/{number}#discussion_r{comment_id}"}
    if reply_to is None:
        created.update(path=fields.get("path"), line=fields.get("line"), start_line=fields.get("start_line"),
                       side=fields.get("side", "RIGHT"), commit_id=fields.get("commit_id"))
        state["threads"][f"PRRT_{comment_id}"] = {"repo": repo, "pull_number": number,
                                                  "comments": [comment_id], "resolved": False}
    else:
        root = find_comment(state, "review_comment", repo, reply_to)
        root_id = root.get("in_reply_to_id") or root["id"]
        root = find_comment(state, "review_comment", repo, root_id)
        created.update({key: root[key] for key in ("path", "line", "start_line", "side", "commit_id")})
        created["in_reply_to_id"] = root_id
        state["threads"][thread_of(state, root_id)]["comments"].append(comment_id)
    state["review_comments"][str(comment_id)] = created
    return comment_view(state, "review_comment", created)


def review_view(found):
    view = {key: value for key, value in found.items() if key not in ("repo", "pull_number")}
    view["user"] = user(found["user"])
    view["pull_request_url"] = f"https://api.github.com/repos/{found['repo']}/pulls/{found['pull_number']}"
    return view


def pull_view(repo, found, listed=False):
    owner = repo.split("/")[0]
    view = {"id": 900000 + found["number"], "number": found["number"], "node_id": f"PR_{repo}#{found['number']}",
            "title": found["title"], "body": found["body"], "state": found["state"], "draft": found["draft"],
            "user": user(found["author"]), "created_at": found["created_at"], "updated_at": found["updated_at"],
            "closed_at": found["merged_at"] if found["state"] == "closed" else None,
            "merged_at": found["merged_at"], "merge_commit_sha": found["merge_commit_sha"],
            "head": {"ref": found["head"], "sha": found["head_sha"], "label": f"{found['head_owner']}:{found['head']}",
                     "repo": {"owner": {"login": found["head_owner"]}}},
            "base": {"ref": found["base"], "repo": {"owner": {"login": owner}, "full_name": repo}},
            "html_url": f"https://github.com/{repo}/pull/{found['number']}"}
    if not listed:
        view["merged"] = found["merged"]
    return view


def issue_view(repo, found):
    return {"id": 800000 + found["number"], "number": found["number"], "node_id": f"I_{repo}#{found['number']}",
            "title": found["title"], "body": found["body"], "state": found["state"],
            "user": user(found["author"]), "created_at": found["created_at"], "updated_at": found["updated_at"],
            "closed_at": found["closed_at"],
            "html_url": f"https://github.com/{repo}/issues/{found['number']}"}


def graphql(state, request):
    fields = dict(request["fields"])
    query = fields.pop("query", "")
    match = re.search(r"\b(query|mutation)\s+(\w+)", query)
    if not match:
        raise Reply(422, {"errors": [{"message": "fake gh: GraphQL needs a named operation"}]})
    operation = match.group(2)
    handler = GRAPHQL.get(operation)
    if handler is None:
        raise Reply(422, {"errors": [{"message": f"fake gh: no GraphQL handler for {operation}"}]})
    return 200, {"data": handler(state, fields)}


def thread_node(state, node_id, thread):
    root = state["review_comments"].get(str(thread["comments"][0])) if thread["comments"] else None
    return {"id": node_id, "isResolved": thread["resolved"], "isOutdated": thread.get("outdated", False),
            "path": root and root["path"], "line": root and root["line"],
            "startLine": root and root["start_line"], "diffSide": root and root["side"],
            "comments": {"nodes": [{"databaseId": c, "id": f"PRRC_{c}",
                                    "url": state["review_comments"][str(c)]["html_url"]}
                                   for c in thread["comments"] if str(c) in state["review_comments"]]}}


def gql_viewer(state, fields):
    return {"viewer": {"login": state["viewer"]}}


def gql_review_threads(state, fields):
    repo = canonical(state, f"{fields['owner']}/{fields['repo']}")
    pull(state, repo, fields["number"])
    nodes = [thread_node(state, node_id, t) for node_id, t in state["threads"].items()
             if t["repo"] == repo and t["pull_number"] == int(fields["number"])]
    size = state.get("thread_page_size")
    if size:
        start = int(fields.get("after") or 0)
        page_info = {"hasNextPage": start + size < len(nodes), "endCursor": str(start + size)}
        nodes = nodes[start:start + size]
    else:
        page_info = {"hasNextPage": bool(state.get("partial_threads")), "endCursor": None}
    return {"repository": {"pullRequest": {"reviewThreads": {"pageInfo": page_info, "nodes": nodes}}}}


def gql_set_resolved(resolved):
    def handler(state, fields):
        thread = state["threads"].get(fields["threadId"])
        if thread is None:
            raise Reply(200, {"errors": [{"message": f"Could not resolve to a node with the global id of '{fields['threadId']}'"}]})
        thread["resolved"] = resolved
        name = "resolveReviewThread" if resolved else "unresolveReviewThread"
        return {name: {"thread": thread_node(state, fields["threadId"], thread)}}
    return handler


def pull_by_node(state, node_id):
    repo, _, number = node_id.removeprefix("PR_").partition("#")
    return pull(state, repo, number)


def gql_set_draft(draft):
    def handler(state, fields):
        found = pull_by_node(state, fields["id"])
        found["draft"] = draft
        name = "convertPullRequestToDraft" if draft else "markPullRequestReadyForReview"
        return {name: {"pullRequest": {"id": fields["id"], "isDraft": draft}}}
    return handler


def gql_merge_state(state, fields):
    repo = canonical(state, f"{fields['owner']}/{fields['repo']}")
    found = pull(state, repo, fields["number"])
    comments = [{"__typename": "IssueComment", "createdAt": c["created_at"], "body": c["body"],
                 "author": {"login": c["user"]}}
                for c in state["issue_comments"].values()
                if c["repo"] == repo and c["issue_number"] == int(fields["number"])]
    pushes = [{"__typename": "HeadRefForcePushedEvent", "createdAt": at} for at in found.get("force_pushed_at", [])]
    return {"viewer": {"login": state["viewer"]}, "repository": {"pullRequest": {
        "state": "MERGED" if found["merged"] else ("CLOSED" if found["state"] == "closed" else "OPEN"),
        "baseRefName": found["base"], "isInMergeQueue": bool(found.get("in_merge_queue")),
        "autoMergeRequest": {"enabledAt": state["now"]} if found.get("auto_merge") else None,
        "mergeCommit": {"oid": found["merge_commit_sha"]} if found.get("merge_commit_sha") else None,
        "commits": {"nodes": [{"commit": {"committedDate": found.get("last_commit_at") or found["created_at"]}}]},
        "timelineItems": {"nodes": comments + pushes}}}}


def pr_merge(state, args):
    strategy = next((a[2:] for a in args if a in ("--merge", "--squash", "--rebase")), None)
    url = next(a for a in args if a.startswith("https://"))
    owner, repo, _, number = url.split("/")[3:7]
    found = pull(state, canonical(state, f"{owner}/{repo}"), number)
    found.setdefault("merge_attempts", []).append({"strategy": strategy, "args": list(args)})
    if strategy in found.get("merge_fail", []):
        save(state)
        sys.stderr.write(f"X Pull request {url} is not mergeable with {strategy}\n")
        return 1
    found.update(merged=True, state="closed", merged_at=state["now"], merge_commit_sha="m" * 40,
                 merge_strategy=strategy)
    save(state)
    return 0


GRAPHQL = {
    "MergeState": gql_merge_state,
    "Viewer": gql_viewer,
    "ReviewThreads": gql_review_threads,
    "ThreadPage": gql_review_threads,
    "ResolveReviewThread": gql_set_resolved(True),
    "UnresolveReviewThread": gql_set_resolved(False),
    "ConvertPullRequestToDraft": gql_set_draft(True),
    "MarkPullRequestReadyForReview": gql_set_draft(False),
}


def emit(request, status, body):
    if 400 <= status or (isinstance(body, dict) and body.get("errors")):
        if body is not None:
            sys.stdout.write(json.dumps(body) + "\n")
        message = body.get("message") if isinstance(body, dict) and "message" in body else body["errors"][0]["message"]
        sys.stderr.write(f"gh: {message} (HTTP {status})\n" if 400 <= status else f"gh: {message}\n")
        return 1
    if request["include"]:
        sys.stdout.write(f"HTTP/2.0 {status} {STATUS_TEXT.get(status, '')}\r\n\r\n")
    if request["silent"] or body is None:
        return 0
    text = json.dumps(body)
    if request["jq"] is not None:
        done = subprocess.run(["jq", "-r", request["jq"]], input=text, stdout=subprocess.PIPE, text=True)
        sys.stdout.write(done.stdout)
        return done.returncode
    sys.stdout.write(text + "\n")
    return 0


def canned(state, argv):
    for response in state["responses"]:
        if argv[: len(response["argv"])] == response["argv"]:
            if response.get("once"):
                state["responses"].remove(response)
                save(state)
            log = os.environ.get("TIMVISHER_AICTL_LOG")
            if response.get("aictl") and log and os.path.isfile(log):
                with open(log, "a", encoding="utf-8") as stream:
                    stream.write(response["aictl"])
            sys.stdout.write(response.get("stdout", ""))
            sys.stderr.write(response.get("stderr", ""))
            return response.get("status", 0)
    sys.stderr.write(f"fake gh: unhandled command: gh {' '.join(argv)}\n")
    return 1


def main(argv):
    repo = hostname = None
    args = list(argv)
    while args and args[0] in ("-R", "--repo"):
        repo, args = args[1], args[2:]
    state = load()
    entry = {"argv": list(argv), "repo": repo, "cwd": os.getcwd(), "gh_token": os.environ.get("GH_TOKEN")}
    if args[:1] != ["api"]:
        record(entry)
        if args[:2] == ["pr", "merge"] and not any(r["argv"][:2] == ["pr", "merge"] for r in state["responses"]):
            try:
                return pr_merge(state, args[2:])
            except Reply:
                sys.stderr.write("fake gh: no such PR\n")
                return 1
        return canned(state, args)
    request = parse_api(args[1:])
    hostname = request["hostname"]
    entry.update(hostname=hostname, method=request["method"], path=request["path"], fields=request["fields"])
    record(entry)
    try:
        status, body = graphql(state, request) if request["path"] == "graphql" else rest(state, request)
    except Reply as reply:
        status, body = reply.status, reply.body
    else:
        save(state)
    return emit(request, status, body)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
