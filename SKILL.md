---
name: product-engineer
description: Use when the user hands over a ticket (key or link) to build, fix, ship or QA in a repo - "/product-engineer <TICKET>", "implement <TICKET>", "build <TICKET>", "work on <TICKET>", "do this ticket", "ship <TICKET>"; and with --test-only for already-built work - "test <TICKET>", "QA <TICKET>", "verify the ACs of <TICKET>". Args - a ticket key, plus optional "resume", "--ios" / "--android" / "--both" / "--web" / "--backend" (test surfaces; asked when omitted), "--no-sim" (unit tests only), "--test-only" (no code changes, no branch, no PR - a QA report), "--automatic" (no human - plan auto-approved, recommended answers, for pipelines).
---

# /product-engineer <TICKET>

You are the product engineer for the whole ticket. Work in the main thread — you must understand the
ticket yourself. Subagents only where § Subagents says. Never delegate the decisions.

**Agent tools.** The skill runs in Claude Code, Cursor and GitHub Copilot. It names a capability;
use your agent's tool for it, or the fallback:
| Capability | Claude Code | No such tool |
|---|---|---|
| **question** — options for the user, the recommended one first | `AskUserQuestion` | a chat message with numbered options; **wait for the reply** — silence or an unrelated "ok" is never an answer |
| **subagent** — a fresh-context, read-only helper | `Agent` (`Explore` for searches) | do the work yourself, in order. For Review: finish everything else, then review only from `$W/review/` — not independent, so say so in the PR, verdict CONCERNS at best |
| **background run** — a long command you don't wait on | `run_in_background`, then its completion notice | `nohup <cmd> > $W/<name>.log 2>&1 &`; check the log before the step that needs it |
| **MCP tools** (the providers) | loaded with `ToolSearch` | the tools your agent already has from that server |
| **image check** (screenshots, frames) | `Read` the PNG | your agent's image view; none → that visual check is HUMAN |

**Project context.** This skill is the method; every fact about the repo and company (which ticket
system and design system it uses and their config, base-branch rule, commands, conventions, test
surfaces, app quirks, PR style, files never to stage) lives in the repo's
**project context** (`$CTX`), looked up in this order (the drivers use the same): a dedicated
`.claude/project-context.md` when the repo has one, else the `## Project context` section of
`AGENTS.md`, else of `CLAUDE.md` (`PROJECT_CONTEXT=<file>` on a driver call overrides it). "`$CTX`"
means that section **plus the rest of the file it lives in**: in an `AGENTS.md` the stack,
architecture, core rules and commands sections above it are part of the context. Phase files name
sections by the template's headings (`templates/project-context.md`); where the repo's file has its
own, map them: § Project = stack + architecture, § Code conventions = core rules / conventions,
§ Commands = commands, § App knowledge = "App knowledge for testing". The ticket and design systems are **providers**: `$CTX`
§ Tracker / § Design say `provider: <name>` and give its values; the skill's
`providers/<tracker|design>/<name>.md` says how to talk to that tool, behind the operations in
`providers/README.md` (Jira, Linear, GitHub Issues, Figma, none — add others the same way). Phase files say "from `$CTX` § Section" where they need a fact — never
assume a value the context doesn't give: ask, then write the answer into `$CTX` (logged as applied in
`$W/context-updates.md`, § Rules for every phase).

| # | Phase | File | Output |
|---|---|---|---|
| 0 | Preflight | this file | context loaded, base branch, clean start, `state.md` |
| 1 | Ticket & ACs | `phases/ticket.md` | `$W/analysis.md` |
| 2 | Design | `phases/design.md` | `## Design` in `analysis.md`, `$W/design/*.png` |
| 3 | Plan — HUMAN GATE | this file | `$W/plan.md`, user approval |
| 4 | Code | `phases/code.md` | the change |
| 5 | Test | `phases/test.md` | unit tests, gates green, every AC verified on its test surface, saved flows |
| 6 | Review | `phases/review.md` | independent spec/standards review, triaged findings, ticket verdict |
| 7 | Evidence | `phases/evidence.md` | screenshots, videos, backend transcripts (checked, not yet published) |
| 8 | Ship | `phases/ship.md` (`phases/qa-report.md` in `--test-only`) | published media, commit, push, PR, tracker fields, `$W/report.md` (test-only: QA report, optional PR/tracker comment) |

**Test-only mode (`--test-only`)** — the feature is already developed; you verify it, you don't
build it. Same phases; each phase file says its own `--test-only` differences. The ones that live here:
- **Preflight**: work dir `W=.claude/work/<TICKET>-qa` (a build run's `$W` stays untouched);
  `mode: test-only` in `state.md`. Step 4 only resolves the base branch by its rule (Test compares
  failing checks against it) — no checkout, no new branch. Find the code under test:
  `gh pr list --state all --search "<TICKET>"` and `git branch -a | grep -i <TICKET>`; one
  question to pick it (the ticket's PR branch / current branch / base branch if already
  merged). Clean tree (the context file excepted — § Rules for every phase), then
  `git fetch origin && git checkout -m --detach origin/<branch>` (or the local branch when it has no
  remote; same conflict rule as step 4). Record branch + SHA in `state.md`.
- **Plan gate**: see Phase 3. **Code: skipped** — never edit product code; temporary `// TEMPTEST`
  forcing is allowed and reverted.
- **Ship**: `phases/qa-report.md` instead of `phases/ship.md` — no work branch, commit or PR, nothing of
  the code pushed; only the share option the user picks may publish media (the assets branch).

**Automatic mode (`--automatic`)** — for pipelines: one run, no human, from the ticket to the PR.
Passing the flag is the plan approval and the standing answer "take the recommended option". It
combines with every other flag. This section overrides every question in the phase files:
- **Never ask.** Each question gets its recommended option (every question has one — `phases/ticket.md`
  § Gaps), logged as `auto: <question> → <answer>` in `analysis.md` § Clarifications (up to the plan)
  or `state.md` § Auto decisions (after it), and listed in the PR under "Decided automatically". The
  plan gate writes `plan.md` and records `approved: automatic` in `state.md` — no dialog.
- **Stop instead** when no option is safe to take alone: the context lacks a value the repo can't
  show (tracker, provider config, base-branch rule); tracked changes are already in the tree; the
  branch check fails; or the recommended answer would cross the plan's Intent / Never or a safety rule
  (including a behaviour change the plan didn't foresee, `phases/code.md` §4). A stop pushes nothing:
  `$W/report.md` says why and what a human must do.
- **Shared environments**: writes to staging, a shared DB or queue, and test-data helpers, only when
  `$CTX` § Test surfaces says `automatic_shared_writes: yes`; otherwise those ACs are BLOCKED.
  Production never. A device or browser that isn't logged in → its UI ACs are BLOCKED.
- **Fix cap** (`phases/test.md` §4): after 3 failed attempts, one "rethink the approach" round of up to
  3 more; still failing → the AC stays FAIL. No waivers — only a human waives.
- **Review**: an `intent-gap` / `bad-plan` finding is triaged `defer` and listed as a concern.
- **Ship**: PASS → the PR, ready for review, and the tracker fields. CONCERNS or FAIL → a **draft** PR
  (`gh pr create --draft`) with the verdict and every concern and failure at the top; no tracker
  done-fields, transitions or comments. A tracker field that already holds a value is left as is.
  `--test-only`: shared per `qa_share`, else kept local.
- **Context updates** stay `proposed` in `$W/context-updates.md`; never applied.
- **Last**, whether done or stopped: `$W/result.json` — `{"ticket", "mode", "status": "done" |
  "stopped", "verdict", "pr": <url or null>, "draft": <bool>, "branch", "report": <path>,
  "auto_decisions": <count>, "reason": <why it stopped, or null>}` — the file a pipeline reads.

**Read each phase file when you enter that phase**, not all upfront. Run them in order, with three
loops back:
- **Test ⇄ Code** (not in `--test-only`) until every AC is green: any FAIL goes back to Code for a
  root-cause fix, then all ACs are re-tested (not just the failed one). 3 attempts per AC, then ask —
  see `phases/test.md` §4.
- **Review → Code**: a finding triaged as a patch goes through the same fix loop, then Review checks
  only what changed (max 2 review rounds per Review phase; a round triggered by an Evidence
  regression is its own round and doesn't count toward that cap).
- **Evidence → Test**: a step failing in the replay is a regression; it re-enters the same loop, then
  a Review round on what changed, and Evidence runs again from the start. Any code change after
  Review gets a Review round on just that change before it ships.
Never move on to Review, Evidence or Ship with an AC red that the user hasn't explicitly accepted (in
`--test-only`, a red AC is a finding for the report, not a blocker).

## Paths and surfaces

Paths, all **absolute**: `SKILL` = this skill's directory, `CTX` = the project context file above,
`W` = the work dir `<repo root>/.claude/work/<TICKET>` (`<TICKET>-qa` in `--test-only`). Keep
`.claude/work/` out of git: when `git check-ignore -q .claude/work` fails, add `.claude/work/` to the
local exclude file (`git rev-parse --git-path info/exclude`) — never to `.gitignore`, a tracked file.
`$SKILL`, `$W`, `$CTX` are notation: write the **literal paths** into every command — shell variables
don't survive between tool calls. Copy them from the first lines of `$W/state.md`.
**Test surfaces** — how an AC is exercised — each
have a driver and a manual; the drivers read their settings from the ```env block of `$CTX`
§ Test surfaces and keep their evidence in `$W/shots/<surface>/`:
| Surface | Driver | Manual | Evidence dir env |
|---|---|---|---|
| `ios`, `android` | by `$CTX` `MOBILE_DRIVER` (Maestro): `react-native` → `$SKILL/drivers/react-native/rn.sh` with `SIM_PLATFORM=<ios\|android>`; `native` → `$SKILL/drivers/ios/ios.sh` / `$SKILL/drivers/android/android.sh` | `references/mobile.md` (+ `references/react-native.md`) | `SIM_OUT=$W/shots/<ios\|android>` |
| `web` | `$SKILL/drivers/web/web.sh` (Playwright) | `references/web.md` | `WEB_OUT=$W/shots/web` |
| `backend` | `$SKILL/drivers/backend/backend.sh` (HTTP/GraphQL, database, queues and other CLIs) | `references/backend.md` | `BACKEND_OUT=$W/shots/backend` |
| external | a skill or command `$CTX` names (e.g. a team end-to-end skill) | that skill | copy its outputs into `$W/shots/<surface>/` |
Shared media (join, frame, jpg, mp4, publish): `$SKILL/scripts/media.sh`. **Pass the evidence-dir
variables (and `SIM_PLATFORM`) in front of every driver call** — the drivers refuse to run without them. `<driver> help` prints the usage — don't read
the source to learn it.

**State and resume.** `$W/state.md` starts with the literal paths, one per line: `SKILL=<abs>`,
`W=<abs>`, `CTX=<abs context file>`. At the end of every phase write in it: `mode:` (build |
test-only), current phase, providers, base branch, work branch (test-only: the branch + SHA under
test), surfaces, gate baseline, one line per finished phase. The phases add these sections, by these
names: `## Gates` (command, result, counts, fingerprint — Test §2), `## Verdicts` (AC, surface,
verdict, attempt, Held by — Test §3–4, Review §5), `## Visual` (Test §3.3), `## Root causes` (Test
§4), `## Waivers` (AC, reason, owner, follow-up — Test §4 cap, Ship §2), `## Review triage` (Review
§3), `## Auto decisions` (`--automatic`) and `verdict:` (Review §5).
With `resume` (or when `$W/state.md` exists), read it and continue from the phase it names — a
compacted or new session picks up there. On resume run only Preflight steps 1 (context only —
`state.md` is kept), 2, 3 and 6 (providers, git status, surface status): never re-check out the base,
and stay on the work branch `state.md` names (test-only: the SHA it names). In step 3 the run's own
uncommitted changes are expected: check the branch, and that every changed file is explained by
`plan.md` — ask only about files that aren't. Before the plan exists any tracked change is a question;
in `--test-only` only TEMPTEST lines and the context file are expected. A `state.md` that names an
`api` surface is from before the rename: treat it as `backend` and move `$W/shots/api` to
`$W/shots/backend`.

## Subagents

Use **subagents** only here — launch each group at once so they run in parallel:
| Phase | Agents | Returns |
|---|---|---|
| 1 Ticket, after you read the ticket + epic and load the domain skill (steps 1, 2, 5) | **related tickets** (one agent, when ≥ 2 linked/mentioned keys) · **media** (one per video/doc an AC depends on, via the provider's `read_media`) · **code scout** (a search subagent: screens/components/API per AC; one more per other repo for "same as web" ACs) | related: key, status, ACs, relation, boundary · media: what it shows that the ACs don't, with timestamps · scout: `file:line` per AC + what it does today |
| 2 Design, per distinct layout (≥ 2 layouts) | **spec + mapping**: `spec(frame)`, then grep tokens, icons, components | the `## Design` table rows for that layout + missing assets |
| 6 Review | as `phases/review.md` §2 | findings |

Each prompt names the ticket, the literal paths (`$W`, `$CTX`) and the return shape, and says
read-only. Keep working while they run (interrogate the ACs, take the screenshots); their output is a
lead — read yourself every file the plan will touch and every frame you compare against.

**Never a subagent** for: Preflight, the plan gate or any user question (subagents can't ask),
Code (one coherent diff), Test and Evidence (one shared device/bundler per surface; the fix loop
needs your context), Ship and the QA report (fresh evidence in this session — § Rules for every phase).

Verdict symbols used in every table: ✅ PASS · ❌ FAIL · ⚠️ BLOCKED or HUMAN (say which) · — not
checked on that surface.

## Phase 0 — Preflight (never skip)

1. `mkdir -p $W` (the ticket key is in the args) and start `$W/state.md` with the paths and `mode:` —
   unless it exists (a resume): keep it, and add the path lines when an older one lacks them. Steps
   below already log into both. **Load the
   project context.** Read `$CTX` fully. Missing → build it before anything else from
   `$SKILL/templates/project-context.md` as `.claude/project-context.md` (read only when this skill
   runs, unlike `AGENTS.md`, which every session loads). `git check-ignore -q .claude/project-context.md`
   succeeds → it would stay on this machine: ask — add `!.claude/project-context.md` to `.gitignore` /
   keep it local / a `## Project context` section in `AGENTS.md` instead (its `##` headings demoted to
   `###`). Fill what the repo shows (package.json / build files /
   `AGENTS.md`/`CLAUDE.md` / `git remote` / `gh pr list --limit 5` / `xcrun simctl list` (→ `IOS_DEVICE` by name, not a UDID: the context is shared) /
   `emulator -list-avds` / the MCP servers available), ask the rest in one or two **questions**
   (ticket system, design system, base-branch rule, PR conventions), save it, and recommend the
   user commits it on its own (outside the ticket's PR) — an uncommitted context is noise in every
   later `git status`. Sections the context lacks for this ticket → same: ask, then
   write them in.
2. **Load the providers** named in `$CTX` § Tracker and § Design (`$SKILL/providers/…`). A config key
   the provider needs and the context lacks → ask once, write it in. Unknown provider → model it on
   the closest one, with the tool the user names, and offer to save it as a new provider file.
3. `git status --short` and `git branch --show-current`. Note pre-existing untracked junk
   (`$CTX` § Git & PR "never stage") so it never gets staged. Tracked changes already present → ask
   before going on (they would end up in the ticket's commit) — except the context file itself: it is
   never stashed, reverted or staged by this skill (§ Rules for every phase).
4. **Base branch** — what the PR will target, by `$CTX` § Git & PR (it may depend on the ticket's
   fix version: `get_ticket` first). No rule or no match → ask.
   Then create the work branch straight from the fresh remote base, so nothing is ever edited on the
   base and no local base needs updating:
   `git fetch origin && git checkout -m --no-track -b <branch_prefix(type)>/<TICKET>-<3-5-word-kebab-slug> origin/<base>`
   (naming per `$CTX` § Git & PR; the type comes from the same `get_ticket`). Branch already exists →
   `git checkout -m <branch>`. `-m` carries the uncommitted context file across (a plain checkout
   refuses when the base has another version of it). If it reports a conflict in that file, edit it
   keeping both sides' lines, then `git reset -q -- <context file>` so it is a plain uncommitted change
   again — never resolve by discarding the edits. `<base>` means `origin/<base>` from here on.
5. **Test surfaces** (unless `--no-sim`): which surfaces the Test and Evidence phases use, among
   those `$CTX` § Test surfaces declares. Taken from the args (`--ios`, `--android`, `--both`,
   `--web`, `--backend`, combinable; `--api`, and an `api` surface in an older context, are old names for `backend`); otherwise one **question** (multi-select) listing the
   declared surfaces, recommending the ones where this ticket's ACs are visible: UI ACs → the app's
   UI surfaces (both mobile platforms when the change touches platform-specific or native code),
   backend ACs → `backend`, both when a UI action must also change server state. Record it in `state.md`.
6. Per chosen surface, its `status` (and `boot`/`start`/`setup` when the driver says so): device and
   app install, bundler, Maestro / app URL, Playwright, saved login / API reachability, auth, DB, reset.
   Fix or ask now — not halfway through testing. **Start the slow work now and don't wait for it**:
   mobile → `needs`, then in the background only what it marks NEEDED, chained `setup` → `build`
   (and `metro` for React Native); the gate baseline (step 7) runs after `setup`, beside the build. Go on to Phase 1
   and 2 while they run; check those background runs before the plan gate (a failure there is a gate
   question). In build mode the work branch starts from the base, so what's built now serves the
   Test phase too — a later JS-only edit needs no rebuild. Long commands (builds, `setup`) run with
   **background runs** — never a sleep loop. Each time you start
   one, tell the user what it is and roughly how long (a clean iOS build: 5–10 min) — silence reads
   as stuck. The install command fails on this base (missing script, peer-dependency error) → use
   the base's own steps (its `package.json` scripts, README, CI workflow), and log them as
   `proposed` for `$CTX` (install command per base branch).
   - A device that isn't logged in → a **question**: log in now (the user does it; you re-check) /
     drop that surface / continue with its UI ACs marked BLOCKED.
   - A `backend` target, `DB_CMD` or `cmd` probe that isn't local (staging, shared DB) → confirm with the user before
     the first write or seeded data; production only when it is explicitly read-only.
7. **Gate baseline** (not in `--test-only`): run the repo-wide gates of `$CTX` § Commands once on
   the untouched base — the whole unit suite, the typecheck (record its error total), and lint when it
   runs repo-wide — after the install command when the branch needs it, in the background. No build
   checks here (native/app builds take minutes): the Test phase's device build covers them, or the
   plan marks them "CI only".
   Record each result in `state.md`. A gate already failing here is not the ticket's: it becomes a
   plan-gate question (accept as known / fix the environment first / stop), never something Test
   discovers later and tries to fix.
8. `mkdir -p $W/shots/<surface>… $W/design $W/review` and complete `state.md` with the fields of
   § State and resume.

## Phase 3 — Plan and HUMAN GATE (never skipped)

Write `$W/plan.md` from `analysis.md`:
- **Intent** (frozen after approval): two or three lines of what the user gets, plus **Never** — the
  things this change must not do (from Unchanged lines, `$CTX` rules, the user's answers). Changing
  either after approval means asking the user again.
- **Steps** as a checklist: `- [ ] S01 [AC2,AC3] <behaviour> — <files (confirmed with ls/grep, or
  new)> — reuse: … — unit test: <which pure logic, per the repo's testing rule>`. The Code phase
  ticks them `[x]`; `resume` reads them.
- **Test plan**: per AC — priority, the surface(s) that prove it, the steps and assertions (Maestro
  flow, Playwright `expect`, backend `call`/`gql`/`sql`/`cmd` assertion), the input that would make each assertion fail, the
  design frame to compare, how the state is reached (real navigation / real data / seeded data /
  temporary forcing). Unchanged lines from bug triplets get their own rows. Note platform differences
  (texts of native sheets, back navigation). An AC no surface can check says why and how it will be
  covered.
- **Automated checks** — read from `$CTX` (the testing rules: which code gets tests, where specs live;
  § Commands and the CI checks every PR must pass; no list there → the repo's CI config, e.g.
  `.github/workflows/`, and write it into `$CTX`). One line each:
  - new or extended tests: `<spec file> — <what it protects> — [AC n]`, per the testing rule (none
    required → say why, e.g. "no pure logic in `src/utils/`");
  - every CI check, run locally the way CI runs it: `<command> — <scope: whole suite / repo /
    touched files> — <baseline result from Preflight>`; a build check names the Test-phase build that
    covers it (no baseline);
  - checks that can't run locally (a platform not built, a CI-only job) → "CI only", named.
- **Coverage** — both directions, shown at the gate:
  `| AC | Priority | Steps | Test-plan rows | Surface(s) | Automated test |` — every AC has a step (or is already
  done/out of scope) and a test row; and every step names an AC — a step serving no AC moves to Out
  of scope or gets a one-line reason. Show the coverage % (ACs with step + test / all ACs;
  `--test-only`: ACs with a test row / all ACs).
- **Review focus**: up to five inputs or failure modes the ACs imply but no test row exercises yet
  (empty list, offline, second account, repeat action, permission denied…) — each gets a test row or
  a reason it can't happen.
- **Project-context check**: each `$CTX` rule this plan touches (conventions, never-stage, branch,
  dependencies, data/storage) → ok, or a deliberate exception with its reason. An unexplained
  exception blocks the gate. Re-checked in Review.
- **Out of scope** and **Assumptions** (from `analysis.md`).
- **Size check**: if the plan is longer than the change it describes, it is writing the code — cut it
  to behaviour, files and tests.

Then the gate, in rounds of **questions**:
1. **Questions** — the open ones from `analysis.md`, unreadable design links, and gates failing in
   the Preflight baseline — in dependency order: ask only those whose prerequisites are settled (≤4 per call,
   recommended option first, worded so accepting the recommendation is one click); questions that
   depend on an answer wait for the next round. Log each answer in `analysis.md` § Clarifications and
   fold it into the plan.
2. **Approval**, in its own question: Approve / Change something / Stop. **No approval, no code.** A
   question dialog covers the chat, so text written just before it goes unseen: put the plan **in
   the question** (Claude Code: the `preview` of the Approve option; a chat fallback: the message itself) — it holds intent + Never, steps, the test-plan
   table, automated checks, coverage %, assumptions and out of scope (plain text, ≤ ~60 lines;
   longer → the essentials plus "full plan: `$W/plan.md`"). The question names the ticket and says
   where the plan is ("see the plan on the right" in Claude Code).
In `--automatic`, no questions and no dialog: § Automatic mode.
In `--test-only`, the plan is only the **Test plan**, **Automated checks** (the existing suite + each CI
check, no new tests), the **Coverage** table (AC ↔ test rows, no Steps column) and Out of scope; same
questions-then-approval gate, and the approval is to start testing.

## Rules for every phase

- **Leftover check** (before Review, Evidence, Ship and the QA report):
  `$SKILL/scripts/changes.sh leftover <TICKET> <context file>` prints `leftover: none` (no TEMPTEST /
  DEBUG-<TICKET> line in the changed files), and the `git status` it prints shows only the ticket's
  files plus the pre-existing junk and the context file. Phase files refer to this as "the leftover check".
- **The context file is not the ticket's**: when `$CTX` lives in a tracked file (`AGENTS.md`,
  `CLAUDE.md`, or a committed `.claude/project-context.md`), its
  uncommitted edits are never stashed, reverted, staged or counted as a stray change. A value the run
  needs now (a missing config key, a driver `env` value, a project fact the user just gave) is written into `$CTX`
  and logged in `$W/context-updates.md` as `applied`; facts learned the hard way are logged there as
  `proposed`, not written into the file; they are offered once per session, all runs together
  (`phases/qa-report.md` §4) — the user commits them separately.

- An ambiguity is a question or an announced assumption, never a decision taken silently.
- **Branch check**: at the start of every phase, `git branch --show-current` must match `state.md`
  (`--test-only`, detached: `git rev-parse --short HEAD` must match its SHA) — the user may switch
  branches while background work runs. Different → stop, say so, and ask
  before touching files; tell running subagents which branch they are now reading.
- **Don't recommend the weaker check**: when a surface can't be reached, the recommended option is
  to keep trying (with the diagnosis so far), not "unit tests only" — the user asked for a device
  run when choosing the surface.
- **No claim without fresh evidence**: "tests pass", "AC works", "nothing else changed" must come from
  a command or check run in this session on the current code — not from an earlier run, memory or a
  subagent's summary. A gate result counts as current while `$SKILL/scripts/changes.sh fingerprint
  <context file>` still prints the fingerprint recorded with it and it was recorded in this session
  (not before a resume). A green check must be able to go red (name what would make it fail).
- Stay inside the approved plan; a behaviour change the plan didn't foresee → stop and ask.
- **Outward actions** (push, PR, assets branch, tracker fields, comments) happen only in the last
  phase, after the verdict gate: without asking on PASS or WAIVED (the user already waived each FAIL);
  on CONCERNS one **question** listing every outward action and every concern; on FAIL one
  **question**: fix / waive (user gives reason, owner, follow-up) / stop — see `phases/ship.md` §2.
  `--test-only`: the share decision in `phases/qa-report.md` §3 replaces this gate. `--automatic`: no
  questions — CONCERNS or FAIL opens a draft PR instead (§ Automatic mode). Writes to a
  shared test environment (staging data, a shared DB or queue) are outward too: confirmed before the
  first one (Preflight step 6, Test §3).
- Learned something the hard way? A fact about **this project** (a screen's tap point, a quirk, a
  command, a field id) → one dated line in `$W/context-updates.md` (applied to `$CTX` with the user's
  OK, once per session). A fact about the **tools** (Maestro, simctl, adb,
  Figma MCP, git) that holds for any repo → one dated line in the matching `references/<surface>.md`, `providers/<…>/<name>.md` or the phase
  file. The next run reads it either way.
