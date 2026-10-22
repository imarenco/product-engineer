# Phase 6 — Independent review

Goal: before recording evidence and shipping, let reviewers that did not write the code try to break
the claim "this ticket is done". The author of a change favours its own conclusions and checks the
first few items carefully and the rest superficially; a fresh context does neither. Runs after Test
is green (or the user accepted the rest), before Evidence.

## 1. Prepare the review pack — `$W/review/`
Run the leftover check (`SKILL.md` § Rules for every phase) first — reviewers must see the code that will ship.
- `diff-r<n>.patch` (round n, from 1): `git add -N <new files> && git diff $(git merge-base origin/<base> HEAD) -- . ':(exclude)<context file>' > $W/review/diff-r<n>.patch` (n = this round)
  — the working tree against where the branch started (new files included; nothing is committed).
  Not `git diff origin/<base>...`: it ignores uncommitted work and comes out empty. `--test-only`: no diff —
  the pack is analysis, plan, verdicts and evidence. The context file is left out: its edits are not
  the ticket's (`SKILL.md` § Rules for every phase).
- `analysis.md`, `plan.md` (intent, Never, coverage, project-context check), `state.md` § Verdicts and
  § Waivers, and the evidence paths (flows, screenshots, transcripts).
- The rules: `$CTX` and the convention docs it names — for the Standards reviewer only; a refuter
  judges the diff against the ACs and the evidence, and doesn't need them.
Reviewers get **paths, not your summary** — your summary is a claim they must verify.

## 2. Reviewers (subagents in parallel, read-only, fresh context — `SKILL.md` § Agent tools; without
subagents, its fallback)
A diff under ~50 changed lines in ≤ 3 files gets **one** reviewer doing both the refuter and the
standards job below (on a 2-file port, two found nothing one wouldn't).
Tell each one: read the pack, change nothing, return findings only as
`{severity: critical|major|minor, class, ac?, file:line?, claim, evidence, suggestion}`.

1. **Refuter (spec).** For every AC: try to knock down its PASS. Does the diff implement the testable
   form (WHEN … SHALL …) — fully, partly, or does it contradict it? Does the evidence prove it: does
   the assertion test the SHALL result, could it fail (an input that turns it red), or is it
   superficial (right screen, wrong content; a step that can't fail; an `optional: true` assertion)? Superficial
   evidence counts as FAIL. Classify everything in the diff against the ACs: `missing`, `partial`,
   `contradicts`, `unrequested` (scope creep). For FAIL verdicts: is the AC really failing, or is the
   test wrong? With more than ~4 ACs, split the ACs between **two** refuters, the P0s first (≤ 3 ACs
   each when possible) — one checking many items inline degrades, and more than two add reading, not
   findings.
2. **Standards.** The diff against `$CTX` (conventions, never-stage, data/storage rules) and the repo's
   convention docs — every finding cites the rule and `file:line`. Plus the **non-functional checks
   the diff triggers**:
   | Diff touches | Check |
   |---|---|
   | auth, tokens, permissions, user data | secrets/PII not logged or stored in plain text; permission checks kept; nothing trusted from the client |
   | network / external calls | error, offline and timeout paths handled; retries bounded; no unhandled promise |
   | lists, renders, queries | no N+1 or unbounded fetch; stable keys; no re-render loops |
   | stored data, migrations, storage keys | reversible or versioned; old data still readable |
   | new interactive UI | accessibility label / role, test id where the repo uses them; contrast per design |
   | money, quotas, compliance | the P0 unhappy paths are tested |

   A check with no measurable threshold is **CONCERNS (unknown)**, never PASS.
3. **Team reviewer** — when `$CTX` § Git & PR names one **for this phase** that runs locally and
   read-only (a review skill/command on the diff), run it too and add its findings. A reviewer that
   posts to a PR or a channel is an outward action: only offered in Ship §8.

`--test-only`: only the refuter, challenging both PASS and FAIL verdicts.

## 3. Triage every finding (you decide; reviewers don't)
| Triage | Meaning | Action |
|---|---|---|
| `patch` | the code is wrong | fix loop (`phases/test.md` §4); `--test-only`: a finding in `state.md` § Findings |
| `test` | the test or evidence is wrong/weak | strengthen the step, re-verify the AC |
| `intent-gap` / `bad-plan` | the ACs or the approved plan didn't cover it, or are wrong | a question — never decide alone (`--automatic`: `defer`); a plan change → below |
| `defer` | real, out of this ticket's scope | follow-up note for the PR / tracker |
| `reject` | the reviewer is wrong | one-line reason with evidence |

Log each as `- <id> <class> <triage>: <one line>` under `## Review triage` in `state.md`, so a later
round never re-argues it.

**The user answers an `intent-gap` / `bad-plan` by changing the plan**: update `analysis.md`
(§ Clarifications) and `plan.md`, then the plan gate's **Approval** question again (`SKILL.md` Phase 3)
— a changed Intent is a new approval. Write it to `state.md` before coding: `phase: code`, a
`replan: r<n> — Review round owed` line (removed after that round), the changed ACs' verdicts as
`PENDING (plan changed)`, and the changed plan steps unticked. Then Code for the new or changed
steps, Test with every AC (new steps for changed test-plan rows; delete the flows of steps the
change made stale — `verify` must not replay an old expectation), and one Review round on that
change, outside the 2-round cap.

## 4. Rounds
After patches and re-tests, a second round reviews **only what changed**: give it
`diff diff-r<n-1>.patch diff-r<n>.patch` (the change since the last round) and the files it touches. Max 2 rounds per Review
phase (a round triggered later by an Evidence regression is separate); anything still open goes to the
user with the evidence (`--automatic`: deferred and listed as a concern; a critical one keeps the
verdict at FAIL).

## 5. Ticket verdict (derived, written to `state.md`, shown in the PR / QA report)
The first that applies:
- **FAIL** — an AC FAIL (whatever its priority), or a gate this change broke (a new failure against
  the Preflight baseline), with no waiver in `state.md` § Waivers; or an unresolved critical finding
  (deferred or not).
- **CONCERNS** — any AC that is HUMAN or BLOCKED, or wasn't checked on any surface (`--no-sim`, or no
  surface can reach it); an AC proven only by forced/TEMPTEST state or a one-off run; an unknown
  non-functional check; deferred major findings; a review done without fresh-context subagents (not
  independent — `SKILL.md` § Agent tools); a `DELTA (concern)` row in `state.md` § Visual; a design link
  read as "no design" (`--automatic`); a deferred `intent-gap` / `bad-plan` finding; a gate `known (baseline, accepted)` in § Gates.
  When the verdict is CONCERNS, any waived ACs are listed with the concerns too.
- **WAIVED** — the only FAILs are ACs or gates the user waived (§ Waivers: reason, owner, follow-up ticket,
  all three going into the PR). Only the user waives; never derive a waiver yourself.
- **PASS** — everything else.

Also fill **Held by** per AC in `state.md` § Verdicts: the durable test that keeps it green in CI
(`file:line` of a unit/integration/e2e test) or `evidence only` — reviewers and future changes need to
know which behaviours a regression would silently break.

Next: `phases/evidence.md`.
