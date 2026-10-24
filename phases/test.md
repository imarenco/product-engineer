# Phase 5 — Test the code (unit tests, gates, surface verification)

Goal: prove the code is right, fast. No recording and no evidence screenshots here — that is the
Evidence phase, run once everything passes — except for forced states (§3), which can't be replayed
later.

## 1. Unit tests
(`--test-only`: none — `modes/test-only.md`, **Test**.)

Which code gets unit tests, where specs live and which spec to copy the style of: `$CTX` § Code
conventions. For each pure function the Code phase extracted, answer before writing a test:
- what it protects, and what change would make it fail;
- why existing specs don't already cover it — extend an existing spec or table instead of duplicating;
- does it need a seam no production caller needs? Then test at the real boundary instead.
One behaviour per test; cover the edge states listed in `analysis.md`.
- **Expected values come from the AC or the design, never from running the code** — copying the
  function's current output into the assertion makes a test that can't fail (tautological).
- **See every new test fail once.** After it passes: break the logic it protects (invert the
  condition, return the old value, revert the fix), run it — it MUST fail for the right reason —
  restore, run again. A test that stays green when the logic is broken protects nothing: fix or drop
  it. For bug fixes the same check is the regression proof: revert the fix → red, restore → green.
Backend repos: when the repo's testing rules ask for them, changed endpoints/resolvers/handlers also
get integration tests (real DB/service per `$CTX` § Commands) — they prove the contract the backend
surface then checks end to end.

## 2. Gates — the plan's Automated checks (never fix unrelated code)
Run every line of `plan.md` § Automated checks: your specs first, then **each CI check the way CI runs
it** (whole suite / whole repo when CI does) — a PR must not be the first place a CI check runs — plus
the local-only commands of `$CTX` § Commands that apply to touched files (format check, typecheck,
forbidden patterns, integration tests in backend repos). Compare each with its Preflight baseline:
only a new failure is yours. Run independent gates (unit suite, typecheck, lint) as parallel background
runs — the wall time is the longest one, not the sum. Inside the fix loop (§4) a round re-runs the
touched specs and the typecheck; the full set runs again before you leave this phase, so the results
Ship reuses are current. Record each result (command, pass/fail, counts, time) in `state.md` § Gates with the
code's fingerprint (`$SKILL/scripts/changes.sh fingerprint <context file>`, taken right before the
run) — Ship reports them and re-runs only what the code has changed under. Respect the notes there (known noise,
backlogs). When the typecheck has a backlog, the total must equal the baseline taken before coding —
and re-check it after the specs are written (a spec's own type error once slipped past a per-file
grep).

## 3. Surface verification (skip only with `--no-sim`)
Run this section once per surface chosen in Preflight, with that driver's evidence dir set
(`SKILL.md` § Paths and surfaces). Read the surface's manual first (`references/<surface>.md`) and the project's
facts for it (`$CTX` § Test surfaces, § App knowledge). An AC proven on several surfaces passes only
when it passes on each; record the verdict per AC and surface.
1. **Prepare once per ticket and surface** — mobile: usually already started in Preflight (step 6);
   otherwise run `needs` and only what it marks NEEDED: `setup` (dependencies changed since the last
   setup — once covers both platforms), `build` per platform (native code changed since this
   driver's last build, or the app was installed by someone else; a background run, minutes).
   `boot` (Android) when no emulator runs. React Native: `references/react-native.md` § Test (Metro,
   `quiet`, `reload`). Native apps: every code change → `needs`, then `build` (minutes) before
   re-testing. Web: `setup` (driver, once per machine), `start` (local app)
   and `login` (the user logs in once by hand) when needed; after a code change, restart/reload the
   app the way `$CTX` says. Backend: `status`; restart the local service after backend code changes;
   seed data per `$CTX`. External surface: follow the named skill's own setup.
2. **Per AC, from the test plan** — the same rules on every surface:
   - a step is a whole state change; `inspect` a new screen before acting on it; wait on the
     screen, not with sleeps; relaunch only for a clean start (mobile: `references/mobile.md` § Maestro
     → Speed).
   - one **step** per state, named `ac<N>-<k>-<state>` (k orders the steps inside the AC:
     `ac5-1-search`, `ac5-2-empty`). A passing `ac*` step is saved to the surface's `flows/` — the
     Evidence phase replays exactly these. Exploratory steps get no name or a `look-` name.
   - each AC is **self-contained**: its first step proves it is where it expects (mobile:
     `assertVisible` of the screen; web: `page.goto` + an `expect`; backend: the request or command itself), and it
     leaves things as the next AC expects (mobile: the screen; backend: the data — or set
     `BACKEND_RESET_CMD`). A tap on the wrong screen still reports success.
   - **every `ac` step must be able to fail.** For each assertion, know the input or code change that
     would turn it red; if there is none, it is decoration — rewrite it. No `optional: true` on an assertion (only
     on the pure wait of `references/mobile.md`), no
     assertion that holds on any screen, no iOS `back` (it does nothing there). Selectors in the
     order the surface manual gives (test id / role first, coordinates last). For a bug AC (build
     mode), the same check must have failed on the unfixed code — the `repro-<n>` step from Ticket
     or plan step S00 — and its `ac` step passes now.
   - **depth follows the AC's priority** (`analysis.md`): P0 — happy and unhappy paths, every chosen
     surface, at least one negative check (the thing that must NOT happen, asserted); P1 — happy path
     and key error states; P2/P3 — one check per state.
   - prove behaviour with **assertions**, not by reading images: Maestro `assertVisible` /
     `assertNotVisible`, Playwright `expect(...)`, `jq`/regex on backend output (API, SQL, queue/CLI). A failing step
     saves `fail-<name>.png` (UI) or a transcript with `Result: FAIL` (backend): read it to diagnose.
   - **looks** are checked in step 3 (visual check), not with assertions.
   - **accessibility** of new or changed interactive UI: once per such state and UI surface — web:
     `await a11y('ac<N>-<k>-<state>', '<css scope of the changed part>')` at the end of the step that
     reaches it (axe-core); mobile: `$D a11y ac<N>-<k>-<state>` on that screen (controls a screen reader
     can't name) — named after the step, so ACs never share a file. Output:
     `shots/<surface>/a11y-ac<N>-<k>-<state>.txt`. A critical/serious violation (web) or an unlabeled control (mobile) on what the diff added or
     changed is the code's: fix it (§4, reproduced by that output, counted against the cap of the AC
     whose state it is); moderate/minor ones and any on untouched elements are left for Review, not
     fixed. `--test-only`: violations on the feature are findings.
   - behaviour the UI can't show (server state, sort order, persistence, counters): the backend surface
     (read back / SQL), the state probe `$CTX` names (e.g. `rn.sh mmkv <key>`, `ios.sh defaults`, `android.sh prefs`), logs where readable,
     or temporary on-screen `// TEMPTEST` output.
   - states real data can't reach (error, empty, a modal variant, a counter at its threshold): first
     a test-data helper `$CTX` § App knowledge names (a real inbound event, seeded records) — real
     data replays in Evidence; these write to shared environments, so one question to the user before
     the first use. Otherwise force them with `// TEMPTEST <TICKET>` code, one at a time: write the
     forced values once as `const NAME = …; // TEMPTEST <TICKET>` lines, then per state: `force <file> NAME=<value>…`
     (it relaunches; native drivers rebuild first — a background run, minutes), then reach the state
     with a `step '<navigate + assertVisible of the forced state>' ac<N>-<k>-<state>-forced` and
     `shot ac<N>-<k>-<state>-forced` (a state on the launch screen: `force … shot <name>` in one call;
     mobile — web: `references/web.md`). A forced step's name ends in `-forced`: it is never
     saved to `flows/` (the forcing is gone by Evidence), so its `ac<N>-<k>-<state>-forced` shot,
     taken now, is its evidence (published with the other `ac*` shots); then remove the forcing. A video of a forced state is **required** when an AC has no replayable flow
     (forcing only) and `$CTX` § Tracker `done_fields` expects a video — record it now, Ship can't:
     `references/mobile.md` § Forced states. After editing a module with
     module-level state, relaunch (hot reload can drop that state without re-running hooks).
3. **Visual check against the design** — UI surfaces, every UI state an AC or the design shows (the
   test plan's "design frame to compare"). Skipped only for a ticket with no UI; when the Design phase
   recorded no design (any provider), compare against what `providers/design/none.md` names instead.
   - How: reach the state, take a `look-` shot, `compare` it with the frame, go through the checklist —
     `references/visual-check.md`.
   - Result per state and surface, in `$W/state.md` § Visual (state, the `ac<N>-<k>-<state>` step that
     reaches it — Evidence compares that step's screenshot — frame, surface, result, differences): **MATCH** · **DELTA** — a difference you can name and justify (platform
     convention, an existing shared component, a design detail the AC overrides) → a design delta for
     the PR / report; one that isn't obvious is recorded `DELTA (concern)` — a concern for Review's
     verdict (decided at Ship's CONCERNS question; `--automatic`: kept and listed) · **MISMATCH** —
     anything else that differs: it is a **FAIL** of that AC (§4 loop).
4. **Verdict per AC and surface**: **PASS** (assertions green and every visual state MATCH/DELTA) ·
   **FAIL** (what differs) · **BLOCKED** (env/data can't
   reach it — why, what the user must do) · **HUMAN** (needs a real finger, device or account: drag,
   pan, scroll in a modal, a real call, store-only APIs, third-party consoles — see `$CTX`
   § App knowledge). Write them into `$W/state.md` § Verdicts.

## 4. The fix loop — Test ⇄ Code until every AC is green
**`--test-only`: skip this section** — `modes/test-only.md`, **No fix loop**.

Any FAIL (an AC, a unit test, a gate or a review finding) sends you back to `phases/code.md`, then
back here. Repeat:

1. **Reproduce in one command** you have already run — the saved flow/spec/backend step that fails, a
   minimal one that asserts the exact symptom, or (visual MISMATCH) the same `look-` shot + `compare`. No reproduction → no fix (it's BLOCKED or flaky: re-run
   once, then report). A Review `patch` finding with no failing command (a missing label, an unhandled
   promise) is reproduced by its cited `file:line`, or by a unit test written to fail on it.
2. **Triage what is wrong**: the code, the test (wrong tap point, stale screen, bad selector,
   tautological expectation), or the AC/plan (the behaviour asked for is impossible or contradicts
   another AC). Only the code costs a fix attempt; a wrong test is fixed in the test; a wrong AC/plan
   goes to the user (`--automatic`: the run stops).
3. **Hypotheses before edits**: list 2–5 ranked, falsifiable causes, each with the observation that
   would confirm or kill it; test them one at a time with probes (state read, tagged debug output
   `// DEBUG-<TICKET>`, a narrower step). Never patch the symptom or weaken the assertion to pass.
4. **Fix** the confirmed cause in the Code phase, under its rules and inside the approved plan (a fix
   that needs a behaviour change the plan didn't foresee → ask). Write the confirmed cause into
   `state.md` § Root causes — it goes into the PR.
5. **Re-test everything, not just the failed AC** — a fix can break an AC that was already green:
   the gates (§2); the fixed AC's own steps again with `step`, under their `ac` names (a passing one is
   saved now — it had no flow); then every saved flow in one call per surface — native app: `needs` →
   `build` first; mobile: `relaunch`, web: restart the app per `$CTX`, then `<driver> verify`
   (backend: `replay`). A step whose flow you changed is re-run with `step` under the same name (it
   overwrites the saved flow).
6. Update `$W/state.md` § Verdicts (AC, surface, verdict, attempt n) and § Attempts (hypothesis →
   change → result, and the failing step's command) — they survive compaction and a resume. Run the leftover check (`SKILL.md` § Rules for every phase) before leaving the phase.
7. Loop while anything is FAIL.

**Cap:** 3 fix attempts per AC, and per gate the change broke (`--automatic`: `modes/automatic.md`). Three failed fixes usually mean the approach is wrong, not the
details: on the 4th failure stop and ask a question with the evidence (what fails, hypotheses tested,
what was tried) — rethink the approach (say which) / accept as known and continue / stop. "Accept"
is a waiver of that AC (or gate): ask in the same round for the reason, owner and follow-up ticket, and
write them into `state.md` § Waivers, naming the AC or the gate — Review derives WAIVED from them and Ship puts them in the PR without
asking again. BLOCKED and HUMAN are not failures of the code — they don't loop; they go
to the user once (`--automatic`: moved on, `modes/automatic.md`).

Leave this phase only when gates are green (no failure beyond the baseline's `known` ones) and every AC is PASS, or the user accepted each
BLOCKED/HUMAN/FAIL (`--no-sim`: gates green, every AC recorded as — not checked; `--automatic`: the
AC and gate caps reached count as accepted, `modes/automatic.md`). Next:
`phases/review.md`.

## Rationalizations — and the answer
| Tempting thought | Do instead |
|---|---|
| "The screenshot looks right" | an assertion on the SHALL result; looks are for design comparison only |
| "Close enough to the design" | name each difference: justified → DELTA, anything else → MISMATCH (FAIL) |
| "It's flaky, skip it" | re-run once; still red → FAIL with the evidence, or BLOCKED with the reason |
| "Small change, no need to re-test the other ACs" | `verify` all saved flows (one call) — a two-line change can break any of them |
| "The test passed first try" | see it fail once (break the logic) — a test that never failed may test nothing |
| "The unit test covers it" | ACs are verified on a surface; unit tests prove logic, not the user-visible result |
| "I'll clean the TEMPTEST/DEBUG code later" | the leftover check (`changes.sh leftover`) before leaving the phase |
