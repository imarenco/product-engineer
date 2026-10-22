# Phase 8 — Ship: publish media, commit, push, PR, tracker

Goal: commit exactly this ticket's change on the work branch Preflight created, push it, open a PR a
reviewer can approve without reading the ticket, and update the tracker the way the team expects.
Naming, base branch, PR style, never-stage files and tracker fields: `$CTX` § Git & PR and § Tracker.

## 1. Final checks
Every claim this phase makes (tests green, ACs pass, nothing else changed) must come from a command
run **in this session on the final diff** — never from memory of an earlier run, a subagent's summary
or "should pass".
- The leftover check passes (`SKILL.md` § Rules for every phase); no debug logs left.
- Gates: `$SKILL/scripts/changes.sh fingerprint <context file>`. Same as the fingerprint recorded with
  the last gate run of this session (`state.md` § Gates) → those results stand, report them. Different, none
  recorded, or recorded before a resume → re-run the Test phase gates and keep their output for the report.
- `git diff --stat`: every file is explained by `plan.md`; nothing else (revert incidental churn such
  as project files a build reordered, per `$CTX` § Git & PR). The context file is not churn — leave it
  as it is (`SKILL.md` § Rules for every phase).

## 2. Gate before publishing — the ticket verdict from Review
- **PASS** → go on without asking: publish + commit + push + PR + tracker update are part of this skill.
- **CONCERNS** → one question listing every concern and every outward action this phase will
  take (assets branch, push, PR, tracker fields): go on / fix first / stop. On "go on", each concern
  is listed in the PR (the reviewer decides whether it blocks merge).
- **WAIVED** → go on without asking: the user already waived each FAIL (Test's cap); each waiver's
  reason, owner and follow-up from `state.md` § Waivers goes into the PR.
- **FAIL** → one question: fix it (back to the loop) / waive it — the user gives reason, owner and
  follow-up ticket, written into § Waivers and the PR / stop here. Never waive on your own.

## 3. Publish the media
Where PR media goes comes from `$CTX` § Git & PR. Runs after the gate above, so nothing leaves the machine before the verdict allows it. The default for GitHub (no API for PR attachments)
is an orphan assets branch `pr-assets/<TICKET>` in the same repo — only media, never merged; keep it
after merge, the PR's images point at its commit:
Run it as one tool call (the `M=` line doesn't survive into another call), with literal paths. The
`setopt` line makes zsh (the Bash tool's shell) drop globs that match nothing, such as a missing
`forced/`; media.sh skips them too and fails only when nothing is left:
```
setopt nullglob 2>/dev/null
M=$SKILL/scripts/media.sh
$M jpg $W/shots/*/ac*.png $W/shots/*/forced/ac*.png          # half-size JPEGs, ~45–100 KB each
$M publish <TICKET> $W/shots/*/ac*.jpg $W/shots/*/forced/ac*.jpg $W/shots/*/workflow.mp4 \
  $W/shots/*/ac[0-9]*.mp4 $W/shots/*/forced/*.mp4
# --test-only adds the failures: $M jpg $W/shots/*/fail-*.png, then the fail-*.jpg in the publish list
```
It commits through a temporary index (working tree and branch untouched), pushes, and prints one
SHA-pinned `https://github.com/<owner>/<repo>/blob/<sha>/<file>?raw=true` URL per file; files under
`shots/` are named by their path below it with `/` → `-` (`shots/ios/ac1-1-x.jpg` → `ios-ac1-1-x.jpg`,
`shots/ios/forced/v.mp4` → `ios-forced-v.mp4`); two files mapping to one name stop the publish. Backend evidence is text:
paste `backend-evidence.md` into the PR body instead of publishing it. Save them to
`$W/media.md` (`<file> <url>` per line) for the PR body.
- In a private repo, images render inline for members only; videos are links (GitHub plays only
  drag-and-drop uploads inline). People without repo access can't open them — `$CTX` § People & process.
- Publish only shots of the finished app — never one showing data you wouldn't paste in the PR text.
- Nothing to publish (e.g. a pure-logic ticket) → say so in `media.md`.
- `--test-only`: only after the user chose to share (`phases/qa-report.md` §3).

## 4. Branch
Preflight created the work branch (`state.md`). Check `git branch --show-current` is it; if the run
somehow sits on the base, `git checkout -b <branch_prefix(type)>/<TICKET>-<slug>` now (the uncommitted
work moves with it).

## 5. Commit
- Stage only the ticket's files: `git add <explicit paths>` — never `-A`, never the never-stage list
  in `$CTX`, never local hacks, never `.claude/`, never the context file. Generated code is committed when the plan
  regenerated it.
- `git diff --cached --stat` must match the plan.
- Message per `$CTX` § Git & PR (e.g. Conventional Commits with the ticket key), ending with the
  Co-Authored-By trailer from the system attribution.
- A failing commit hook is fixed at its cause, never skipped with `--no-verify`.

## 6. Push and PR
`git push -u origin <branch>`, write `$W/pr.md`, then create the PR with the command and options in
`$CTX` § Git & PR (base = Preflight's base branch). Body in the team's house style (`$CTX` points at
an example PR): plain sentences and bullets for a reviewer who hasn't read the ticket, no filler.
Media URLs come from `$W/media.md`. Use the house style's sections, and always include the verdict
line, the AC table and the evidence (they are what reviewers check). Default shape when the context
has none:
```
<1–3 sentences: what the user sees now that they didn't before.>

**Verdict: PASS | CONCERNS (<the concerns>) | WAIVED (<reason, owner, follow-up>)** · coverage <n>/<m> ACs

▶️ Full test run: [iOS (Ns)](<ios-workflow.mp4 URL>) · [Android (Ns)](<android-workflow.mp4 URL>) · [Web (Ns)](<web-workflow.mp4 URL>)   ← only the surfaces tested

## Acceptance criteria
| AC | Priority | <one column per surface tested: iOS · Android · Web · Backend> | How it was checked | Held by | Evidence |
|---|---|---|---|---|---|
| #1 <short paraphrase> | P0–P3 | ✅ / ❌ / ⚠️ / — | <steps, assertion, the input that would fail it, design frame> | <`spec file:line` or evidence only> | <img src="<ios-ac1-…jpg URL>" width="180"> [▶️ video](<ac1.mp4 URL>) · Backend: transcript `ac1-…` below |

<details><summary>Backend evidence (request/command transcripts)</summary>

<contents of shots/backend/backend-evidence.md>
</details>

## What changes
- `<file or area>`: <behaviour change>, <reuse / new token / new util> …
- Decisions taken with product/user during the ticket (from `analysis.md` § Clarifications), the
  assumptions applied, and design deltas left on purpose.
- Bug fixes: the confirmed root cause in one or two sentences (from `state.md` § Root causes).

**Merge danger:** <two-way door: plain code, revertable> | <one-way door: migration, stored-data or
storage-key change, native/store release, public API/event shape, permissions> — blast radius: <who
or what is affected if it's wrong, and how to roll back>.

## Test plan
Surfaces (only those tested: devices / browser / backend environment), build of this branch:
- [x] <AC-level check with the concrete observation>
- [x] Unit: `<spec file>` — <what it protects> (N tests)
- [x] CI checks run locally: `<command>` ✅ (<counts>) · … — "CI only: <check>" for the rest
- [ ] <not run: drag/pan, a real device, a state the environment can't reach> — why
Design: <design link> (frames compared: …)

<details><summary>Design vs app (visual check)</summary>

| State | Frame | <one column per UI surface> | Differences |
|---|---|---|---|
| <state> | <frame name> | ✅ MATCH / ⚠️ DELTA <img src="<ios-ac1-1-…-vs-design.jpg URL>" width="360"> | <none / the delta and why> |
</details>

Refs: <TICKET>

<the agent's attribution line, when it gives one>
```
An AC with several states gets one image per state in its Evidence cell. A forced state is labelled
"(forced)". Follow-ups the user agreed to (e.g. backend work) get a short section with a draft.
After creating it, `gh pr view --json body` and check every media URL is in the body.

## 7. Tracker fields
Fill the fields `$CTX` § Tracker says the team expects when development is done (e.g. a
demo-video field the tracker's automation checks) — no extra question: it's part of this skill.
- Value: what the context says (e.g. the published full-run video URL from `$W/media.md`; a field
  that holds one link gets one surface's video — the one `done_fields` names, else ask). Forced
  states only (no replayable flow) → the forced video Test recorded for this
  (`shots/<surface>/forced/ac<N>-forced.mp4`, `phases/test.md` §3); none recorded, or no video
  possible (`--no-sim`, a backend-only ticket) → leave the field unset and say so in the report, with
  what the tracker's automation will do about it if the context says — the user decides what to attach.
- `set_field(key, field, value)` from the tracker provider, with the field ids of its `done_fields`
  config. A field that already holds a real value (not a placeholder) → ask before replacing it.
- Read it back to confirm (the provider says how). On a permission/workflow error, don't retry blindly: report it and give
  the user the value to paste.
- Links into a private repo can't be opened by people without access — say so in the report and
  offer the local video for upload elsewhere.

## 8. Report
Write `$W/report.md`, update `state.md` to done, and answer in chat with:
- the ticket verdict, the PR URL, branch, base, assets branch;
- `| AC | <surface columns> | Evidence |`;
- design deltas accepted or left, decisions taken with the user;
- tests added (count, what they protect) and gate results;
- not checked and why (HUMAN/BLOCKED), risks;
- which tracker fields were set (and to what), plus the local path of `workflow.mp4`.

Offer, don't do: a review post in the team's channel (`$CTX` § Git & PR), a tracker `comment` with
the AC table, a `transition` of the ticket's status.

Project facts in `$W/context-updates.md` are offered once per session, all runs together — see `phases/qa-report.md` §4.
