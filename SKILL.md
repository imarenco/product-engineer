---
name: product-engineer
description: Use when the user hands over a ticket (key or link) to build, fix, ship or QA in a repo - "/product-engineer PROJ-123", "implement PROJ-123", "build PROJ-123", "work on PROJ-123", "do this ticket", "ship PROJ-123"; and with --test-only for already-built work - "test PROJ-123", "QA PROJ-123", "verify the ACs of PROJ-123"; and with --pr-comments once its PR is reviewed - "address the review comments on PROJ-123", "fix the PR comments". Args - a ticket key, plus optional "resume", "--ios" / "--android" / "--mobile" (both) / "--web" / "--backend" (test surfaces; asked when omitted), "--no-sim" (unit tests only), "--test-only" (no code changes, no branch, no PR - a QA report), "--pr-comments" (answer the open review comments on the ticket's PR - fix, re-test, push, reply), "--automatic" (no human - plan auto-approved, recommended answers, for pipelines).
---

# /product-engineer <TICKET>

You are the product engineer for the whole ticket. Work in the main thread — you must understand the
ticket yourself. Subagents only where § Subagents says. Never delegate the decisions.

**Agent tools.** The skill runs in Claude Code, Cursor and GitHub Copilot. It names a capability;
use your agent's tool for it, or the fallback:

| Capability | Claude Code | No such tool |
|---|---|---|
| **question** — options for the user, the recommended one first | `AskUserQuestion` | a chat message with numbered options; **wait for the reply** — silence or an unrelated "ok" is never an answer |
| **subagent** — a fresh-context, read-only helper | `Agent` (`Explore` for searches) | do the work yourself, in order. For Review: finish the Test phase and the review pack first, then review only from `$W/review/` — not independent, so say so in the PR, verdict CONCERNS at best |
| **background run** — a long command you don't wait on | `run_in_background`, then its completion notice | `nohup bash -c '<cmd>; echo "EXIT $?"' > $W/<name>.log 2>&1 &` (a `<cmd>` with single quotes → put it in `$W/<name>.sh` and run that). Finished only when the log's last line is `EXIT <n>`, passed only on `EXIT 0`. Work on meanwhile; when nothing else is left, the bounded wait below |
| **MCP tools** (the providers) | loaded with `ToolSearch` | the tools your agent already has from that server |
| **image check** (screenshots, frames) | `Read` the PNG | your agent's image view; none → that visual check is HUMAN |
| **skill** (a domain, design or review skill `$CTX` or a provider names) | `Skill` | read that skill's `SKILL.md` (the path `$CTX` gives, or the MCP server's `skill://…` resource); neither → go on without it, logged as an assumption |

The fallback's bounded wait (under 2 min; not finished → call it again):
`for i in $(seq 11); do tail -1 $W/<name>.log | grep -q '^EXIT' && break; sleep 10; done`

**Project context** (`$CTX`) holds every fact about the repo and company — tracker and design tool
with their config, base-branch rule, commands, conventions, test surfaces, app quirks, PR style,
files never to stage. Lookup (the drivers use the same): `.claude/project-context.md`, else the
`## Project context` section of `AGENTS.md`, else of `CLAUDE.md` (`PROJECT_CONTEXT=<file>` on a driver
call overrides it); `$CTX` is that section plus the rest of its file. Phase files name sections by
`templates/project-context.md`'s headings; map the repo's own (§ Project = stack + architecture,
§ Code conventions = core rules, § Commands = commands, § App knowledge = "App knowledge for
testing"). The tracker and the design tool are **providers**: `$CTX` § Tracker / § Design say
`provider: <name>`, and `providers/<tracker|design>/<name>.md` says how to use it (Jira, Linear,
GitHub Issues, Figma, none — a new one per `providers/README.md`). Never assume a value `$CTX`
doesn't give: ask, write the answer in, log it `applied` in `$W/context-updates.md`.

| # | Phase | File | Output |
|---|---|---|---|
| 0 | Preflight | this file | context loaded, base branch, clean start, `state.md` |
| 1 | Ticket & ACs | `phases/ticket.md` | `$W/analysis.md` |
| 2 | Design | `phases/design.md` | `## Design` in `analysis.md`, `$W/design/*.png` |
| 3 | Plan — HUMAN GATE | `phases/plan.md` | `$W/plan.md`, user approval |
| 4 | Code | `phases/code.md` | the change |
| 5 | Test | `phases/test.md` | unit tests, gates green, every AC verified on its test surface, saved flows |
| 6 | Review | `phases/review.md` | independent spec/standards review, triaged findings, ticket verdict |
| 7 | Evidence | `phases/evidence.md` | screenshots, videos, backend transcripts (checked, not yet published) |
| 8 | Ship | `phases/ship.md` (`phases/qa-report.md` in `--test-only`) | published media, commit, push, PR, tracker fields, `$W/report.md` (test-only: QA report, optional PR/tracker comment) |

**Modes** — read the file when it applies, before Preflight; it overrides the phases where it says so:

| Mode | When | Read |
|---|---|---|
| test-only | `--test-only`, or `state.md` `mode: test-only` | `modes/test-only.md` — verify an existing feature: no code, no branch, a QA report |
| PR comments | `--pr-comments`, or `state.md` `flags:` has it while `pr_round:` isn't done | `modes/pr-comments.md` — answer the review comments on the ticket's open PR: fix, re-test, push, reply |
| automatic | `--automatic`, or `state.md` `flags:` has it while continuing an unfinished run (a resume, a compaction) — not a stopped run's resume, a new run or a new PR round | `modes/automatic.md` — no human: it answers or stops at every question |
| resume | `resume`, or `$W/state.md` exists (with `--pr-comments`: only an unfinished round) | `modes/resume.md` — which run, where to pick up, finished runs |
| new context | no `$CTX` found (Preflight step 1) | `modes/new-context.md` — build it first |

**Read each phase file when you enter that phase**, not all upfront. The loops back live in the phase
files: Test ⇄ Code until every AC is green (`phases/test.md` §4); Review → Code for a `patch` finding,
or a plan change for an intent gap (`phases/review.md` §3–4); Evidence → Test for a replay regression
(`phases/evidence.md` §2). Any code change after Review gets a Review round on just that change before
it ships. Never move on to Review, Evidence or Ship with an AC red that the user hasn't explicitly
accepted (test-only and automatic: their mode files).

## Paths and surfaces

Paths, all **absolute**: `SKILL` = this skill's directory, `CTX` = the project context file, `W` =
the work dir `<repo root>/.claude/work/<TICKET>` (`<TICKET>-qa` in `--test-only`). `git check-ignore
-q .claude/work/` fails (keep the trailing slash) → add `.claude/work/` to the local exclude file
(`git rev-parse --git-path info/exclude`), never to `.gitignore`. `$SKILL`, `$W`, `$CTX` are notation:
write the **literal paths** (the first lines of `$W/state.md`) into every command — shell variables
don't survive between tool calls.

**Test surfaces** — how an AC is exercised. Each has a driver and a manual; the drivers read their
settings from the ```env block of `$CTX` § Test surfaces and keep their evidence in
`$W/shots/<surface>/`:

| Surface | Driver | Manual | Evidence dir env |
|---|---|---|---|
| `ios`, `android` | by `$CTX` `MOBILE_DRIVER` (Maestro): `react-native` → `$SKILL/drivers/react-native/rn.sh` with `SIM_PLATFORM=<ios\|android>`; `native` → `$SKILL/drivers/ios/ios.sh` / `$SKILL/drivers/android/android.sh` | `references/mobile.md` (+ `references/react-native.md`) | `SIM_OUT=$W/shots/<ios\|android>` |
| `web` | `$SKILL/drivers/web/web.sh` (Playwright) | `references/web.md` | `WEB_OUT=$W/shots/web` |
| `backend` | `$SKILL/drivers/backend/backend.sh` (HTTP/GraphQL, database, queues and other CLIs) | `references/backend.md` | `BACKEND_OUT=$W/shots/backend` |
| external | a skill or command `$CTX` names (e.g. a team end-to-end skill) | that skill | copy its outputs into `$W/shots/<surface>/` |

Shared media (join, frame, jpg, mp4, publish): `$SKILL/scripts/media.sh` — `compare`, `join`, `frame` and
`jpg` are macOS only (swift, sips): elsewhere compare by viewing both PNGs, publish PNGs, and the joined
videos are BLOCKED (a `REPLAY FAILED: video…` is then no regression); say so at Preflight. **Pass the evidence-dir
variable (and `SIM_PLATFORM` for `rn.sh`) on every driver call** — the drivers refuse to run without
it. The manual's command table is the usage; `<driver> help` only for an option it lacks — never the source.

**State.** `$W/state.md` starts with the literal paths, one per line: `SKILL=<abs>`, `W=<abs>`,
`CTX=<abs context file>`. At the end of every phase write in it: `mode:` (build | test-only),
`flags:` (the surfaces, `--no-sim`, `--automatic`, `--pr-comments`), `approved:` (user | automatic, once the plan gate
passes), `phase:` (the current one; `done` / `stopped` at the end), providers, base branch, work
branch (test-only: the branch + SHA under test), surfaces, gate baseline, one line per finished
phase. The phases add these sections, by these names: `## Gates` (command, result, counts,
fingerprint, time — Test §2), `## Verdicts` (AC, surface, verdict, attempt, Held by — Test §3–4, Review
§5), `## Attempts` (AC or gate, n, hypothesis → change → result, the failing step's command — Test §4),
`## Visual` (Test §3.3), `## Root causes` (Test §4), `## Waivers` (AC or gate, reason, owner,
follow-up — Test §4 cap, Ship §2), `## Review triage` (Review §3), `## Findings` (`--test-only`: id,
AC, steps, expected vs actual, evidence, likely `file:line`; the QA report is written from it),
`## PR comments` (`--pr-comments`: id, author, triage, reply status), `## Auto decisions`
(`--automatic`), `verdict:` (Review §5), and these lines when they apply: `stopped:` (phase — reason),
`resumed:` (time), `replan:` (Review §3), `pr_round:` (n, `n done`), `<surface>: no replay — why`
(Evidence §2). **Attempt n** = the number of fixes
already made for that AC (0 before the first fix). After a context compaction mid-run, re-read
`state.md` and carry on as `modes/resume.md` (**Where to pick up**) says.

## Subagents

Use **subagents** only here — launch each group at once so they run in parallel:

| Phase | Agents | Returns |
|---|---|---|
| 1 Ticket, after you read the ticket + epic and load the domain skill (steps 1, 2, 5) | **related tickets** (one agent, when ≥ 2 linked/mentioned keys) · **media** (one per video/doc an AC depends on, via the provider's `read_media`) · **code scout** (a search subagent: screens/components/API per AC; one more per other repo for "same as web" ACs) | related: key, status, ACs, relation, boundary, a declined/reverted one's reason quoted · media: what it shows that the ACs don't, with timestamps · scout: `file:line` per AC + what it does today |
| 2 Design, per distinct layout (≥ 2 layouts) | **spec + mapping**: `spec(frame)`, then grep tokens, icons, components | the `## Design` table rows for that layout + missing assets |
| 6 Review | as `phases/review.md` §2 | findings |

Each prompt names the ticket, the literal paths (`$W`, `$CTX`) and the return shape, and says
read-only (the media agent writes only into `$W/media/`). Keep working while they run (interrogate the ACs, take the screenshots); their output is a
lead — read yourself every file the plan will touch and every frame you compare against.

**Never a subagent** for: Preflight, the plan gate or any user question (subagents can't ask),
Code (one coherent diff), Test and Evidence (one shared device/bundler per surface; the fix loop
needs your context), Ship and the QA report (fresh evidence in this session — § Rules for every phase).

Verdict symbols used in every table: ✅ PASS · ❌ FAIL · ⚠️ BLOCKED or HUMAN (say which) · — not
checked on that surface.

## Phase 0 — Preflight (never skip)

1. `mkdir -p $W` (the ticket key is in the args) and start `$W/state.md` with the paths and `mode:`
   (a resumed run or a PR-comments round keeps its own: `modes/resume.md`, `modes/pr-comments.md`). Steps below already log into both. **Load the
   project context**: read `$CTX` fully. None → `modes/new-context.md` first. Sections it lacks for
   this ticket → ask, then write them in.
2. **Load the tracker provider** named in `$CTX` § Tracker (`$SKILL/providers/tracker/<name>.md`; the
   design provider is loaded in Phase 2). A config key it needs and the context lacks → ask once,
   write it in. Unknown provider → model it on the closest one, with the tool the user names, and
   offer to save it as a new provider file.
3. `git status --short` and `git branch --show-current`. Note pre-existing untracked junk
   (`$CTX` § Git & PR "never stage") so it never gets staged. Tracked changes already present → ask
   before going on (they would end up in the ticket's commit) — except the context file (§ Rules for
   every phase).
4. **Base branch** — what the PR will target, by `$CTX` § Git & PR (it may depend on the ticket's
   fix version: `get_ticket` first). No rule or no match → ask.
   Then the work branch. A re-run of the ticket reuses its branch: `git fetch origin`, then
   `git branch -a -i --list "*<TICKET>" "*<TICKET>-*"` (so PROJ-1 isn't PROJ-12;
   a bare number, GitHub Issues: `"*/<n>-*"` only), ignoring `pr-assets/*` (evidence, not code), and
   `gh pr list --state open --search "<TICKET>" --json headRefName` — one branch (local and/or remote) → "Branch already exists" below; several → a question (`--automatic`: the open PR's,
   else stop). None → create it straight from the fresh remote base, so nothing is ever edited on the
   base and no local base needs updating:
   `git checkout -m --no-track -b <branch_prefix(type)>/<TICKET>-<3-5-word-kebab-slug> origin/<base>`
   (naming per `$CTX` § Git & PR; the type comes from the same `get_ticket`). Branch already exists →
   `git checkout -m <branch>` (a remote-only one is created tracking origin), then — when it is on origin — `git merge --ff-only origin/<branch>`: the
   developer may have pushed since (not a fast-forward → a question). `-m` carries the uncommitted
   context file across (a plain checkout refuses when the base has another version of it). If it
   reports a conflict in that file, edit it keeping both sides' lines, then
   `git reset -q -- <context file>` so it is a plain uncommitted change again — never resolve by
   discarding the edits. From here on, compare against `origin/<base>` (just fetched), never a
   local `<base>`.
5. **Test surfaces** (unless `--no-sim`): which surfaces the Test and Evidence phases use, among
   those `$CTX` § Test surfaces declares. Taken from the args (`--ios`, `--android`, `--mobile` = both,
   `--web`, `--backend`, combinable; `--api` and an `api` surface in an older context are old names
   for `backend`, `--both` for `--mobile`); otherwise one **question** (multi-select) listing the declared surfaces,
   recommending the ones where this ticket's ACs are visible: UI ACs → the app's UI surfaces (both
   mobile platforms when the change touches platform-specific or native code), backend ACs →
   `backend`, both when a UI action must also change server state. Record it in `state.md`.
6. Per chosen surface, its `status` (and `boot`/`start`/`setup` when the driver says so): device and
   app install, bundler, Maestro / app URL, Playwright, saved login / API reachability, auth, DB,
   reset. Fix or ask now — not halfway through testing. **Start the slow work now and don't wait for
   it**: mobile → `needs`, then as background runs only what it marks NEEDED, chained `setup` → `build`
   (and `metro` for React Native); the gate baseline (step 7) runs after `setup`, beside the build (native iOS: after it —
   `references/mobile.md` § Native apps). Go
   on to Phase 1 and 2 while they run; check them before the plan gate (a failure there is a gate
   question). In build mode the work branch starts from the base, so what's built now serves the Test
   phase too. Long commands (builds, `setup`) are always background runs — never a sleep loop (the fallback's bounded wait excepted); each
   time you start one, tell the user what it is and roughly how long (a clean iOS build: 5–10 min).
   The install command fails on this base (missing script, peer-dependency error) → use the base's
   own steps (its `package.json` scripts, README, CI workflow), and log them as `proposed` for `$CTX`.
   - A saved login (web: one per repo, shared by every ticket) → confirm it is live and is the account
     the ACs need: one step on a page only that user sees. Expired or wrong → as not logged in.
   - A device that isn't logged in → a **question**: log in now (the user does it; you re-check) /
     drop that surface / continue with its UI ACs marked BLOCKED.
   - A `backend` target, `DB_CMD` or `cmd` probe that isn't local (staging, shared DB) → confirm with
     the user before the first write or seeded data; production only when it is explicitly read-only.
   - A `WEB_URL` / `API_URL` that isn't local runs the base's code, not the work tree: the change must
     reach it — a local service pointed at that environment, or a deploy command `$CTX` names (an
     outward action before Ship — the one exception to that rule: confirmed first; `--automatic`: only
     with `automatic_deploy: yes`). Neither
     → the ACs that need the change are BLOCKED; never a fix loop against a target that lacks the code.
7. **Gate baseline**: run once on the untouched base (a reused branch with commits of its own: in a
   temporary worktree: `git worktree add <scratch dir> $(git merge-base origin/<base> HEAD)`, the install
   command first, `git worktree remove` after), as parallel background runs, every gate the
   plan will compare against — the whole unit suite, the typecheck (record its error total), lint
   when it runs repo-wide, and every other CI check or `$CTX` § Commands gate that runs locally
   (integration tests, format check, forbidden patterns), after the install command when the branch
   needs it. No build checks (native/app builds take minutes): the Test phase's device build covers
   them, or the plan marks them "CI only". Record each result in `state.md` § Gates, with the merge-base SHA it ran on. A gate already
   failing here is not the ticket's: it becomes a plan-gate question (accept as known / fix the
   environment first / stop), never something Test discovers later and tries to fix. Accepted →
   `known (baseline, accepted)` in § Gates with the failing test ids (Test compares the sets, not
   the totals): it never blocks Test, and Review and the PR list it.
8. `mkdir -p $W/shots/<surface>… $W/design $W/review` and complete `state.md` (§ Paths and surfaces, **State**).

## Phase 3 — Plan and HUMAN GATE (never skipped)

`phases/plan.md`: the plan, its questions and the Approval question. **No approval, no code** — in
every mode (`--automatic` and `--test-only` change how it is given: their mode files).

## Rules for every phase

- **Leftover check** (before Review, Evidence, Ship and the QA report):
  `$SKILL/scripts/changes.sh leftover <TICKET> <context file>` prints `leftover: none` (no TEMPTEST /
  DEBUG-<TICKET> line in the changed files), and the `git status` it prints shows only the ticket's
  files plus the pre-existing junk and the context file. Phase files refer to this as "the leftover
  check".
- **The context file is not the ticket's**: when `$CTX` lives in a tracked file (`AGENTS.md`,
  `CLAUDE.md`, or a committed `.claude/project-context.md`), its uncommitted edits are never stashed,
  reverted, staged or counted as a stray change. A value the run needs now (a missing config key, a
  driver `env` value, a project fact the user just gave) is written into `$CTX` and logged in
  `$W/context-updates.md` as `applied`. Facts learned the hard way — a fact about **this project**
  (a tap point, a quirk, a command, a field id) — are one dated `proposed` line there, not written
  into the file; they are offered once per session, all runs together — when the user ends the session or asks: one
  multi-select of every unapplied `proposed` line in `.claude/work/*/context-updates.md`, the rest
  marked `declined` — and
  the user commits them separately. A fact about the **tools** (Maestro, simctl, adb, Figma MCP, git)
  that holds for any repo → one dated line in the matching `references/<surface>.md`,
  `providers/<…>/<name>.md` or the phase file. The next run reads it either way.
- An ambiguity is a question or an announced assumption, never a decision taken silently.
- **Branch check**: at the start of every phase, `git branch --show-current` must match `state.md`
  (`--test-only`, detached: `git rev-parse --short HEAD` must match its SHA) — the user may switch
  branches while background work runs. Different → stop, say so, and ask before touching files; tell
  running subagents which branch they are now reading.
- **Don't recommend the weaker check**: when a surface can't be reached, the recommended option is
  to keep trying (with the diagnosis so far), not "unit tests only" — the user asked for a device
  run when choosing the surface.
- **No claim without fresh evidence**: "tests pass", "AC works", "nothing else changed" must come from
  a command or check run in this session on the current code — not from an earlier run, memory or a
  subagent's summary. A gate result counts as current while `$SKILL/scripts/changes.sh fingerprint
  <context file>` still prints the fingerprint recorded with it and it was recorded in this session
  (each § Gates line carries its time; a resume writes `resumed: <time>` — older lines are stale). A green check must be able to go red (name what would make it fail).
- Stay inside the approved plan; a behaviour change the plan didn't foresee → stop and ask.
- **Outward actions** (push, PR, assets branch, tracker fields, comments) happen only in the last
  phase (a confirmed test deploy to a non-local target excepted: Preflight step 6), after the verdict gate in `phases/ship.md` §2 (test-only: the share decision in
  `phases/qa-report.md` §3). Writes to a shared test environment (staging data, a shared DB or queue)
  are outward too: confirmed before the first one (Preflight step 6, Test §3).
