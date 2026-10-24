# Phase 8 — Ship: publish media, commit, push, PR, tracker

Goal: commit exactly this ticket's change on the work branch Preflight created, push it, open a PR a
reviewer can approve without reading the ticket, and update the tracker the way the team expects.
Naming, base branch, PR style, never-stage files and tracker fields: `$CTX` § Git & PR and § Tracker.

## 1. Final checks
Every claim this phase makes comes from a command run in this session on the final diff (`SKILL.md`
§ Rules: no claim without fresh evidence).
- The leftover check passes (`SKILL.md` § Rules for every phase); no debug logs left.
- Gates: `$SKILL/scripts/changes.sh fingerprint <context file>`. Same as the fingerprint recorded with
  the last gate run of this session (`state.md` § Gates) → those results stand, report them. Different, none
  recorded, or recorded before a resume → re-run the Test phase gates and keep their output for the report.
- `git diff --stat`: every file is explained by `plan.md`; nothing else (revert incidental churn such
  as project files a build reordered, per `$CTX` § Git & PR). The context file is not churn — leave it
  as it is (`SKILL.md` § Rules for every phase).

## 2. Gate before publishing — the ticket verdict from Review
`--automatic`: no questions — PASS or WAIVED as below; CONCERNS or FAIL → a draft PR (`modes/automatic.md`).
- **PASS** → go on without asking: publish + commit + push + PR + tracker update are part of this skill.
- **CONCERNS** → one question listing every concern and every outward action this phase will
  take (assets branch, push, PR, tracker fields): go on / fix first / stop. On "go on", each concern
  is listed in the PR (the reviewer decides whether it blocks merge).
- **WAIVED** → go on without asking: the user already waived each FAIL (Test's cap); each waiver's
  reason, owner and follow-up from `state.md` § Waivers goes into the PR.
- **FAIL** → one question: fix it (back to the loop) / waive it — the user gives reason, owner and
  follow-up ticket, written into § Waivers and the PR, then the verdict is derived again
  (`phases/review.md` §5) and this gate applies to the new one / stop here. Never waive on your own.

## 3. Publish the media
First, when the branch is on origin: `git fetch origin` and `git merge-base --is-ancestor origin/<branch> HEAD`
— not an ancestor (someone pushed during the run) → §6's rejected-push answer now, before anything
is published. The recipe — destination, the one-call publish block, the names it produces, what never to publish:
`references/publish.md`. Save publish's output as `$W/media.md` for the PR body.
- `--test-only`: only after the user chose to share (`phases/qa-report.md` §3).

## 4. Branch
Preflight created the work branch (`state.md`). Check `git branch --show-current` is it; if the run
somehow sits on the base, `git checkout -b <branch_prefix(type)>/<TICKET>-<slug>` now (the uncommitted
work moves with it).

## 5. Commit
- Stage only the ticket's files: `git add <explicit paths>` — never `-A`, never the never-stage list
  in `$CTX`, never local hacks, never `.claude/`, never the context file. Generated code is committed when the plan
  regenerated it.
- `git diff --cached --stat` must match the plan. Nothing staged (a round that changed no code) → no
  commit; push only when the branch is ahead of origin.
- Message per `$CTX` § Git & PR (e.g. Conventional Commits with the ticket key), ending with the
  Co-Authored-By trailer your agent's attribution gives, when it gives one.
- A failing commit hook is fixed at its cause, never skipped with `--no-verify`.

## 6. Push and PR
`git push -u origin <branch>` (rejected because someone pushed to the branch during the run → the
code was tested on a branch that no longer exists: a question — merge their work and re-test from
Test, or stop; `--automatic`: stop), write `$W/pr.md`, then create the PR with the command and options in
`$CTX` § Git & PR (base = Preflight's base branch). Body in the team's house style (`$CTX` points at
an example PR): plain sentences and bullets for a reviewer who hasn't read the ticket, no filler.
Media URLs come from `$W/media.md`. Use the house style's sections, and always include the verdict
line, the AC table and the evidence (they are what reviewers check). Default shape when the context
has none:
```
<1–3 sentences: what the user sees now that they didn't before.>

**Verdict: PASS | CONCERNS (<the concerns>) | WAIVED (<reason, owner, follow-up>) | FAIL (<the failing ACs and gates>)** · coverage <n>/<m> ACs

▶️ Full test run: [iOS (Ns)](<ios-workflow.mp4 URL>) · [Android (Ns)](<android-workflow.mp4 URL>) · [Web (Ns)](<web-workflow.mp4 URL>)   ← only the surfaces tested

## Acceptance criteria
| AC | Priority | <one column per surface tested: iOS · Android · Web · Backend; none tested (`--no-sim`): one Verdict column, — not checked> | How it was checked | Held by | Evidence |
|---|---|---|---|---|---|
| #1 <short paraphrase> | P0–P3 | ✅ / ❌ / ⚠️ / — | <steps, assertion, the input that would fail it, design frame> | <`spec file:line` or evidence only> | <img src="<ios-ac1-…jpg URL>" width="180"> [▶️ video](<ios-ac1.mp4 URL>) · Backend: transcript `ac1-…` below |

<details><summary>Backend evidence (request/command transcripts)</summary>

<contents of shots/backend/backend-evidence.md>
</details>

## What changes
- `<file or area>`: <behaviour change>, <reuse / new token / new util> …
- Decisions taken with product/user during the ticket (from `analysis.md` § Clarifications), the
  assumptions applied, and design deltas left on purpose. Whenever any were made (`--automatic`, now or before a resume): a
  **Decided automatically** list — every `auto:` line from `analysis.md` § Clarifications and `state.md` § Auto decisions.
- Bug fixes: the confirmed root cause in one or two sentences (from `state.md` § Root causes).

**Merge danger:** <two-way door: plain code, revertable> | <one-way door: migration, stored-data or
storage-key change, native/store release, public API/event shape, permissions> — blast radius: <who
or what is affected if it's wrong, and how to roll back>.

## Test plan
Surfaces (only those tested: devices / browser / backend environment), build of this branch:
- [x] <AC-level check with the concrete observation>
- [x] Unit: `<spec file>` — <what it protects> (N tests)
- [x] Accessibility (<axe tags> / screen-reader labels) on <states>: <no violations on changed elements | what's left>
- [x] CI checks run locally: `<command>` ✅ (<counts>) · … — "CI only: <check>" for the rest
- [ ] `<command>` ❌ — fails on `<base>` too (accepted at the plan gate)
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
A PR for this branch already exists (`gh pr view <branch> --json number,url,isDraft` succeeds — a re-run
of a shipped ticket) → don't create one: `gh pr edit <number> --body-file $W/pr.md`; `--automatic`
(not in a PR-comments round: `modes/pr-comments.md` decides) also sets its draft state by the verdict: PASS or WAIVED and `isDraft` → `gh pr ready <number>`;
any other verdict → `gh pr ready <number> --undo` (back to draft). Its URL
is the `pr` of `result.json`.
After creating or updating it, `gh pr view --json body` and check every media URL is in the body.

## 7. Tracker fields
Fill the fields `$CTX` § Tracker says the team expects when development is done (e.g. a
demo-video field the tracker's automation checks) — no extra question: it's part of this skill.
- Value: what the context says (e.g. the published full-run video URL from `$W/media.md`; a field
  that holds one link gets one surface's video — the one `done_fields` names, else ask; `--automatic`: the first tested surface's). Forced
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
Write `$W/report.md`, set `phase: done` in `state.md`, and answer in chat with:
- the ticket verdict, the PR URL, branch, base, assets branch;
- `| AC | <surface columns> | Evidence |`;
- design deltas accepted or left, decisions taken with the user;
- tests added (count, what they protect) and gate results;
- not checked and why (HUMAN/BLOCKED), risks;
- which tracker fields were set (and to what), plus the local path of `workflow.mp4`.

`--automatic`: write `$W/result.json` last (`modes/automatic.md`).

Offer, don't do: a review post in the team's channel (`$CTX` § Git & PR), a tracker `comment` with
the AC table, a `transition` of the ticket's status.

Project facts in `$W/context-updates.md`: offered once per session (`SKILL.md` § Rules for every phase).
