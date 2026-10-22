# Phase 8 (test-only) — QA report

Replaces `phases/ship.md` when the run has `--test-only`. Goal: tell the team, with evidence, whether
the already-developed feature meets every AC, and exactly what fails if not. **No work branch, no
commit, no product-code change; nothing of the code is pushed** — only the share option the user
picks in §3 may publish media (the assets branch, `phases/ship.md` §3).

## 1. Leave the tree as you found it
- The leftover check passes (`SKILL.md` § Rules for every phase), then `git status --short`: nothing
  tracked may be modified except the context file (left as it is). Any
  change left by forcing code → `git checkout -- <file>` (it was test scaffolding, never a fix).
- Note the exact code tested: branch and `git rev-parse --short HEAD`.

## 2. Write `$W/report.md`
```
# <TICKET> — QA report (test-only)
Tested: <branch> @ <sha> (PR #N if any) · <date> · surfaces: <the ones tested, from `$CTX` § Test surfaces> · <environment>
Verdict (derived as in `phases/review.md` §5): ✅ PASS — ready | ⚠️ CONCERNS — <which> | ❌ FAIL — <N> ACs fail

## Acceptance criteria
| AC | Priority | <one column per surface tested> | How it was checked | Held by | Evidence |
|---|---|---|---|---|---|
| #1 <paraphrase> | P0–P3 | ✅/❌/⚠️/— | <steps, assertions, design frame> | <test file:line / evidence only> | <screenshot / video / transcript> |

## Findings (one per FAIL, most severe first)
### F1 — AC #N: <what is wrong, in user terms>
**In short:** You <do X>. You see <Y>. You should see <Z>.  ← one plain line, no code words
- Platform(s): … · Severity: blocker / major / minor (cosmetic)
- Steps to reproduce: 1. … 2. … 3. …
- Expected (AC / design): … · Actual: …
- Evidence: `fail-<step>.png`, clip, design frame
- Likely cause: `<file>:<line>` — <one or two sentences, from reading the code; say "unconfirmed">

## Design deltas (pass with notes)
(From `state.md` § Visual: each DELTA with its `-vs-design.png`; a MISMATCH is a finding above, severity minor unless it hides or breaks something.)
## Not checked and why (HUMAN / BLOCKED)
## Automated checks on this branch (the existing suite and each CI check, one run each, with results)
```
A FAIL is reported, never fixed here — the fix belongs to the developer of the ticket (or a later
run of this skill without `--test-only`).

**Per finding, ready to file** (the user files sub-bugs by hand — don't make them ask):
- `$W/subbug-F<n>.md`: **Title** (`<Platform>: <screen> – <symptom>`, ≤ 90 chars), **Description**
  (the "In short" line + context), **Steps to reproduce**, **Expected / Actual**, **AC** it breaks,
  **Where in the code** (`file:line`, "likely, unconfirmed"), **Evidence** (image names).

## 3. Share — only with the user's OK (outward-facing)
`--automatic`: `qa_share` if set, else keep it local — never a question.
`$CTX` § Tracker `qa_share` names a standing choice (e.g. `ticket comment`) → do that, announced in
the chat ("posting to <TICKET> as usual"), no question. No `qa_share` → one question,
recommended option first, plus "Always do this" variants; an "always" answer is written to `$CTX`
as `qa_share` (logged `applied` in `$W/context-updates.md`):
- **Comment on the ticket's PR** (when one exists): publish the media first (`phases/ship.md` §3,
  `fail-*` images included),
  then `gh pr comment <N> --body-file $W/report-pr.md` (the report with the published URLs in place
  of local paths; same image/table conventions as `phases/ship.md`).
- **Comment on the ticket** — the tracker provider's `comment(key, markdown)`: report text, media
  links if published.
- **Keep it local**: the user shares `$W/report.md` and the videos themselves.

## 4. Answer in chat
The verdict line, the AC table, the findings (each with its "In short" line and its
`subbug-F<n>.md`), what wasn't checked, where the report and videos are, and what was shared. Update
`state.md` to done.

Append one line to the session log `.claude/work/qa-log.md` (create it if missing):
`<date> | <ticket link> | <verdict> | <sub-bug: title (filed: link, or "to file")>` — the user asks
for "the list of tickets and sub-bugs" at the end of a QA day; answer from this file (check the
tracker for sub-bugs filed since: the ticket's children created today, from `get_related`; tracker
`none`: this log is the only record).

Project facts in `$W/context-updates.md`: don't offer them after every run. When the user ends the
session or asks, collect the `proposed` lines from every `.claude/work/*/context-updates.md` not yet
applied into **one** multi-select question; apply the chosen ones, mark the rest `declined`.
