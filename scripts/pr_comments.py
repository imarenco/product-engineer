"""The open review comments of a PR, compact, and replies to them (gh CLI, run inside the repo).

  python3 -I pr_comments.py list <pr>                  what still needs an answer, one block per item
  python3 -I pr_comments.py reply <pr> <id>[,<id>…] <body-file>

Open = an unresolved review thread whose last comment is neither yours, the PR author's, nor a reply
`reply` posted; a review summary or conversation comment that no `reply` has answered (an answer
typed by hand isn't seen: triage it `skip`). Ours = the token's account, the PR author, and any bot
comment carrying the hidden marker (a pipeline's replies). Ids: T<n> a review thread, R<n> a review
summary, C<n> a conversation comment. Replying to a T id answers in its thread; R/C ids are answered
together in one conversation comment that names them. Each item shows its author's association with
the repo (OWNER, MEMBER, COLLABORATOR, CONTRIBUTOR, NONE…). `reply` only answers ids open right now.
"""
import json, re, subprocess, sys

QUERY = """query($owner:String!,$repo:String!,$n:Int!){viewer{login}
repository(owner:$owner,name:$repo){pullRequest(number:$n){url author{login}
reviewThreads(last:100){totalCount nodes{isResolved isOutdated path line originalLine
  root:comments(first:1){nodes{databaseId}}
  comments(last:20){nodes{databaseId body authorAssociation author{login __typename}}}}}
reviews(last:50){totalCount nodes{databaseId state body authorAssociation author{login __typename}}}
latestOpinionatedReviews(first:100){nodes{state author{login __typename}}}
comments(last:100){totalCount nodes{databaseId body authorAssociation author{login __typename}}}}}}"""
MARK = "<!-- product-engineer: answered %s -->"
MARK_RE = re.compile(MARK % "([^>]*)")
BODY_CAP = 1500  # shortcut: a longer body is cut (a bot's summary at 300); the full text is on the PR page (url printed)


def gh(*args, stdin=None):
    r = subprocess.run(["gh", *args], input=stdin, capture_output=True, text=True)
    if r.returncode:
        sys.exit("gh %s failed: %s" % (args[0] if args[0] != "api" else " ".join(args[:2]), r.stderr.strip()[:300]))
    return r.stdout


def who(a):
    a = a or {}
    return (a.get("login") or "ghost") + (" (bot)" if a.get("__typename") == "Bot" else "")


def login(c):
    return (c.get("author") or {}).get("login")


def text(s, bot=False):
    # hidden markers and collapsed sections are tooling noise (bot summaries are mostly that)
    s = re.sub(r"<!--.*?-->", "", s or "", flags=re.S)
    s = re.sub(r"<details[^>]*>.*?</details>", "[collapsed details]", s, flags=re.S).strip()
    cap = 300 if bot else BODY_CAP
    return s if len(s) <= cap else s[:cap] + " … (%d more chars)" % (len(s) - cap)


def line(c, summary=False):
    # a bot's summary is mostly boilerplate; its code comments are real findings and stay whole
    a = c.get("author") or {}
    return "%s [%s]: %s" % (who(a), c.get("authorAssociation") or "?", text(c.get("body"), summary and a.get("__typename") == "Bot"))


def is_ours(c, ours):
    a = c.get("author") or {}
    return a.get("login") in ours or (a.get("__typename") == "Bot" and MARK_RE.search(c.get("body") or "") is not None)


def number(pr):
    if not re.fullmatch(r"[0-9]+", pr or ""):
        sys.exit("the PR is a number, e.g. 123 (got %r)" % pr)
    return int(pr)


def fetch(pr):
    out = gh("api", "graphql", "-f", "query=" + QUERY, "-F", "owner={owner}", "-F", "repo={repo}", "-F", "n=%d" % pr)
    try:
        d = json.loads(out)
    except ValueError:
        sys.exit("gh api graphql: not JSON: %s" % out[:200])
    if not isinstance(d, dict):
        sys.exit("gh api graphql: unexpected response: %s" % out[:200])
    if d.get("errors"):
        sys.exit("gh api graphql: %s" % d["errors"][0].get("message"))
    p = ((d.get("data") or {}).get("repository") or {}).get("pullRequest")
    if not p:
        sys.exit("no pull request #%d in this repo" % pr)
    return d["data"]["viewer"]["login"], p


def open_items(me, p):
    # in a pipeline the token's account (viewer) isn't the developer: the PR author's words count as answers too
    ours = {me, login(p)} - {None}  # a deleted author (ghost) mustn't make every ghost comment ours
    items = []
    for t in p["reviewThreads"]["nodes"]:
        cs, root = t["comments"]["nodes"], t["root"]["nodes"]
        if t["isResolved"] or not cs or not root or is_ours(cs[-1], ours):
            continue
        where = "%s:%s" % (t["path"] or "?", t["line"] or t["originalLine"] or "?")
        # the id is the thread's first comment: the replies endpoint takes only that, and it never changes
        items.append(("T%d" % root[0]["databaseId"], where + (" (outdated: the code moved since)" if t["isOutdated"] else ""),
                      [line(c) for c in cs]))
    mine = [c.get("body") or "" for c in p["comments"]["nodes"] if is_ours(c, ours)]
    answered = set(re.findall(r"\b[RC][0-9]+\b", " ".join(m for b in mine for m in MARK_RE.findall(b))))
    for kind, nodes in (("R", p["reviews"]["nodes"]), ("C", p["comments"]["nodes"])):
        for c in nodes:
            cid = "%s%d" % (kind, c["databaseId"])
            if is_ours(c, ours) or cid in answered or not text(c.get("body")):
                continue
            label = "review %s" % c["state"].lower().replace("_", " ") if kind == "R" else "conversation"
            items.append((cid, label, [line(c, summary=True)]))
    return items


def main(a):
    if len(a) == 2 and a[0] == "list":
        me, p = fetch(number(a[1]))
        items = open_items(me, p)
        for cid, where, lines in items:
            print("== %s  %s" % (cid, where))
            print("\n".join(lines))
        # shortcut: only the newest 100 threads / 50 reviews / 100 comments are read; past that, say so
        for key, cap in (("reviewThreads", 100), ("reviews", 50), ("comments", 100)):
            if p[key]["totalCount"] > cap:
                print("warning: %d %s, only the newest %d read — check the older ones on the PR page" % (p[key]["totalCount"], key, cap))
        # latestOpinionatedReviews keeps a reviewer whose review was re-requested; latestReviews drops them
        changes = sorted({login(r) for r in p["latestOpinionatedReviews"]["nodes"] if r["state"] == "CHANGES_REQUESTED"
                          and login(r) and (r.get("author") or {}).get("__typename") != "Bot"})
        print("changes requested by: %s" % (", ".join(changes) or "nobody"))
        print("%d open (you: %s, author: %s) — %s" % (len(items), me, login(p), p["url"]))
    elif len(a) == 4 and a[0] == "reply":
        pr, ids = number(a[1]), list(dict.fromkeys(a[2].split(",")))
        try:
            body = open(a[3]).read().strip()
        except OSError as e:
            sys.exit("reply: can't read the body file: %s" % e)
        if not body or any(not re.fullmatch(r"[TRC][0-9]+", i) for i in ids):
            sys.exit("reply: ids are T<n> / R<n> / C<n> from `list`, and the body file must not be empty")
        threads, others = [i for i in ids if i[0] == "T"], [i for i in ids if i[0] != "T"]
        if threads and others:
            sys.exit("reply: a T id is answered in its own thread — reply to it separately from R/C ids")
        current = {cid for cid, _, _ in open_items(*fetch(pr))}
        gone = [i for i in ids if i not in current]
        if gone:
            sys.exit("reply: not open on #%d now (answered, resolved, or not on this PR): %s" % (pr, " ".join(gone)))
        for t in threads:
            gh("api", "repos/{owner}/{repo}/pulls/%d/comments/%s/replies" % (pr, t[1:]), "-f", "body=" + body + "\n\n" + MARK % t)
            print("replied: %s" % t)
        if others:
            gh("pr", "comment", str(pr), "--body-file", "-", stdin=body + "\n\n" + MARK % " ".join(others))
            print("replied: %s" % " ".join(others))
    else:
        sys.exit(__doc__.split("\n\n")[1])


if __name__ == "__main__":
    main(sys.argv[1:])
