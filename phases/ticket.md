# Phase 1 — Read the ticket and analyze the ACs

Goal: understand what the ticket asks better than its author wrote it down, and write it in
`$W/analysis.md`. Every gap becomes a question or an explicit assumption for the plan gate — never a
silent decision.

## Tracker provider
`$CTX` § Tracker names it (`provider: jira`, …) and gives its config (ids, AC format, key pattern,
fields, media readers, standing defaults). Load `$SKILL/providers/tracker/<provider>.md` (Preflight
already did) and use its operations — `get_ticket`, `get_related`, `read_media`. No tracker (`provider: none`) → the task comes from the conversation or a
file (`providers/tracker/none.md`).

## Read, in this order
Steps 1, 2 and 5 yourself; then steps 3, 4 and 6 run as parallel subagents (`SKILL.md` § Subagents)
while you start interrogating the ACs. Their results feed the same sections below.
1. **The ticket** — `get_ticket(key)`. The ACs are where the config's `ac_format` says. Also read
   what `read_also` lists (summary/value sections, notes) — they carry intent the
   ACs omit. Read **every comment**: product/QA decisions there override the description ("AC #5 only
   if we can do it easily" is a scope decision). No AC block → derive ACs from the description, mark
   each `DERIVED`.
2. **Parent epic**: one `get_ticket`, for the feature's goal and the sibling scope.
3. **Related tickets** — `get_related(ticket)`: every link plus every ticket key / URL in the
   description and comments. For each: summary, status, its ACs. Classify:
   - *dependency* — must exist first; is it merged? `git log --oneline --all --grep=<KEY>`;
   - *sibling* — owns part of the UI this ticket hosts; draw the boundary (theirs vs ours). A sibling
     already in testing or done is code that exists — find it and reuse it, don't redo it;
   - *context only*.
   A linked ticket that was declined or reverted: read why — the reason often constrains this one
   (e.g. a compliance decline).
4. **Media and docs** — `read_media(url)` for videos, pages and images. Read them
   when an AC depends on behaviour shown only there; otherwise list them as unread. Unfetchable inline
   images: say so; the design is the source of truth. Design links: collect them here, read them in
   `phases/design.md`.
5. **Domain knowledge first**: when `$CTX` § Tracker lists `domain_skills`, load the one matching the
   ticket's area (payments, search, onboarding…) before searching the code — it maps the code and
   names the traps faster than grep.
6. **Prior art in the code**: `git log --oneline -15 --grep=<KEY>` (reopened or resumed work), then
   locate the screens/components each AC touches (grep the visible strings, screen names, API
   operations) and read those files fully. Data the app doesn't fetch yet → check the schema/API
   location the repo's architecture/data-layer rules name; how other repos (web, backend) do it →
   the cross-repo lookup they name. "Same as on web/current" → find the actual behaviour in that code; never guess it.

## Interrogate every AC
- **Who** triggers it, **where** (exact screen and state), **what** changes, what the user sees after.
- Edge states: empty, loading, error, offline, long text, many items, first use.
- Account shape: roles, sub-accounts, permissions, subscription states, feature flags / remote config.
- Side effects: caches, filters, other tabs, persisted state, navigation back.
- Conflicts between ACs, duplicated ACs, and ACs that contradict existing behaviour.
- "Same as current/web" → write down what current/web actually does.
- Requirements the app alone can't meet (e.g. state shared across devices with no backend field) →
  a question with options (scope down + follow-up ticket / wait for backend).

**Make every AC testable.** Restate it as `WHEN <trigger / state> THE <app/system> SHALL <observable
result>` — one line per behaviour (split ACs that bundle several). The SHALL part is what the test
asserts. An AC you can't write this way (no observable result, two readings, a vague word like
"properly", "fast", "same as before" without a reference) is a gap, not a guess.

**Bug tickets** (an issue type the tracker config's `branch_prefix` maps to `fix`, unless `$CTX`
§ Tracker lists `bug_types`) — and, in any ticket, a **bug AC**: one that states a current wrong
behaviour ("shows the old results", "crashes when…"). For each such AC write the triplet
- Current: `WHEN <condition> THEN the app <wrong behaviour>` — reproduce it on the base as soon as a
  surface for it is ready (backend: now; a device: once Preflight's build is installed), as a step
  named `repro-<n>` (drivers never save it as a flow; keep its failure output for the PR's
  root-cause note). Not reproducible by the plan gate → it is the plan's first step, `S00
  reproduce`, before any code (`--no-sim`: a unit or integration test written to fail on the base). `--test-only`: no reproduction — the AC's step on the code under test
  is the check;
- Expected: `WHEN <condition> THEN the app SHALL <right behaviour>`;
- Unchanged: `WHEN <neighbouring condition> THEN the app SHALL CONTINUE TO <existing behaviour>` —
  the behaviour the fix must not break. Every Unchanged line becomes its own test-plan row.

**Give every AC a risk priority** — it sets how hard the Test phase tries to break it. Ground it in
what the ticket or code says, not in risks that are common elsewhere:
| Priority | When | Test depth |
|---|---|---|
| P0 | money/billing, auth/permissions, data loss or corruption, compliance/legal limits, a behaviour that broke before | happy + unhappy paths, every chosen surface, at least one negative check, a durable automated test where the repo allows |
| P1 | the ticket's main user flow | happy path + key error states |
| P2 | secondary states, copy, layout | one check per state |
| P3 | cosmetic | one look, design comparison |

## Gaps → questions or assumptions
Label each gap `[Gap]` (missing), `[Ambiguity]` (two readings) or `[Conflict]` (contradiction), then
rank by impact × uncertainty (scope > security/data loss > what the user sees > technical detail):
- **Questions** (at most ~5 per gate, highest first): only where no reasonable default exists and the
  answer changes what gets built or tested. Each has *Why it matters* and a recommended answer. Never
  ask for a fact the ticket, the code, the design or another repo can answer — look it up.
- **Assumptions** (everything else): the reasonable default you will apply, stated in one line. They
  are shown at the plan gate and approved with it — never silent. `$CTX` § Tracker may list the
  team's standing defaults ("don't ask about these").

## Write `$W/analysis.md`
```
# <TICKET> — <summary>
Intent (one paragraph, in the user's terms) · Type · Epic · Fix version · Status · Team
## ACs
| # | Verbatim | Testable form (WHEN … SHALL …) | Priority | States / edge cases | How to prove it (surface, assertion) | Gap |
## Bug triplets (bug tickets only)
| AC | Current | Expected | Unchanged (SHALL CONTINUE TO) |
## Related tickets
| Key | Status | Relation (dependency/sibling/context) | Boundary / what we reuse |
## Existing code
files + what each does today, per AC (`--test-only`: the implementation under test, so findings can point at it)
## Questions for the user
1. [Gap|Ambiguity|Conflict] <question> — Why it matters: … — Recommended: …
## Assumptions
- <default applied> (instead of asking: <the gap>)
## Clarifications
### <YYYY-MM-DD>
- Q: <question> → A: <answer>
```
After each answer: log it under Clarifications and **rewrite the affected AC rows** so no outdated
text remains (the log keeps the history; the table is always current). `resume` and the PR's
"Decisions" both read this.

Record the issue type (Preflight step 4 already used it for the work branch; keep it for the PR) and the fix version (Preflight base
branch). A ticket whose status says it isn't ready for development → mention it in the questions.
