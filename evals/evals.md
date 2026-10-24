# Evals — check a change to this skill against real tickets

Before keeping a change to the skill, run the scenarios below with the changed skill and with a
snapshot of the previous version (copy the skill folder first), in parallel subagents — each with
`isolation: "worktree"` and its skill copy inside that worktree (runs check out branches and edit the
context file, so they can't share one tree), and copy the current context file (`.claude/project-context.md`, or
`AGENTS.md` with its `## Project context`) into each worktree, since the committed one may not have it — stopping each
where the scenario says (default: the plan gate; the QA report for `--test-only`). Scenario 10
(`--automatic`) pushes and opens a real PR, and scenario 11 replies on one: run them only against a
fork or a throwaway remote and tracker. Grade the two `$W` folders with the
assertions; keep the change only if it doesn't lose any assertion the old version passed.

## Scenarios
Pick real tickets from your own repo that match each row, and keep them fixed between runs.

The surface flags only say where the ticket is developed and tested; each one routes to a driver
(`SKILL.md` § Paths and surfaces):
| Flag | Driver | Evidence |
|---|---|---|
| `--ios` | React Native: `drivers/react-native/rn.sh` with `SIM_PLATFORM=ios`; native: `drivers/ios/ios.sh` (Maestro) | `$W/shots/ios/` |
| `--android` | React Native: `drivers/react-native/rn.sh` with `SIM_PLATFORM=android`; native: `drivers/android/android.sh` (Maestro) | `$W/shots/android/` |
| `--web` | `drivers/web/web.sh` (Playwright) | `$W/shots/web/` |
| `--backend` | `drivers/backend/backend.sh` (HTTP / GraphQL, SQL, queues and other CLIs) | `$W/shots/backend/` |

Flags combine (`--ios --android`, same as `--mobile`; `--web --backend`; …). No flag → Preflight asks;
`--no-sim` → unit tests only, no driver.

| # | Prompt | Why it's a good test |
|---|---|---|
| 1 | `/product-engineer <UI-TICKET> --ios` (stop at the gate) | UI ticket with a Figma section of state frames and sibling tickets |
| 2 | `/product-engineer <LOGIC-TICKET> --ios` (stop at the gate) | logic-heavy, a declined predecessor ticket, an AC the app can't meet alone (cross-device state) |
| 3 | `/product-engineer <UI-TICKET> --test-only --ios` | already-built feature: must not touch product code |
| 4 | a repo with no project context (no `.claude/project-context.md`, no section in AGENTS.md or CLAUDE.md) | Preflight must draft the context and ask only the unknowns |
| 5 | a backend ticket in a service repo with `--backend` (stop at the gate) | no UI: design `none`, API/SQL/queue test rows, reproduction step for a bug, non-local target confirmed |
| 6 | `/product-engineer <UI-TICKET> --android` (stop at the gate) | same ticket on the other platform: emulator boot, Android coordinates (px), no iOS work |
| 7 | `/product-engineer <WEB-TICKET> --web` (stop at the gate) | web UI: Playwright `expect` rows, local app start or a deployed URL, saved login |
| 8 | `/product-engineer <UI-TICKET> --ios --android` (stop after Evidence) | both platforms in one run: every UI AC verified and recorded on each |
| 9 | `/product-engineer <NATIVE-TICKET> --ios` in a native app (`MOBILE_DRIVER=native`; stop after Test) | `ios.sh`: a build after every code change, state probed with `defaults` |
| 10 | `/product-engineer <UI-TICKET> --ios --automatic` (headless, no answers given) | a pipeline run: no question asked, a PR at the end, `result.json` written |
| 11 | after 10, in 10's worktree: `/product-engineer <TICKET> --pr-comments` on 10's PR with review comments: a real bug, a style nit, a question, one to push back on, a request outside the ACs (stop at the gate) | every comment triaged, none silently dropped or obeyed |

## Assertions (each must be checkable from the files, not from the chat)
- `analysis.md`: every AC has a testable form (WHEN … SHALL …) and a priority; every gap is either a
  question (≤ ~5, with Why it matters + Recommended) or an Assumption; related tickets classified.
- Scenario 2: the declined predecessor's reason appears as a constraint; the AC the app can't meet
  alone is raised as a question, not silently implemented or dropped.
- `plan.md`: steps are a checklist with AC tags; coverage table covers every AC both ways with a %;
  review focus present; project-context check present; nothing coded before approval.
- Test plan rows name the input that would make each assertion fail; no `optional: true` on an assertion
  (the `extendedWaitUntil … optional` wait is allowed).
- Scenario 3: `git status` shows no product-code change at the end; a QA report with a derived verdict.
- Scenario 4: `.claude/project-context.md` exists (or the AGENTS.md section, when the user chose it at
  the gitignore question) with the template's sections; unknowns asked, not invented.
- Scenario 5: every AC's test row is a `backend.sh` call/gql/sql/cmd with a jq/regex assertion that can fail;
  a bug AC has a reproduction row; the plan names the environment and whether it is local.
- Scenario 6: React Native — every `rn.sh` call carries `SIM_PLATFORM=android`; native — every call is
  `android.sh` with `SIM_OUT`; `state.md` surfaces = android only;
  no iOS `build` or `boot`.
- Scenario 7: test rows are Playwright steps with an `expect` that can fail; every `web.sh` call
  carries `WEB_OUT`; the plan says whether the app is started locally (`WEB_START_CMD`) or deployed.
- Scenario 8: `state.md` § Verdicts has an iOS and an Android entry per UI AC; an AC passes only when it
  passes on both; `$W/shots/ios/flows` and `$W/shots/android/flows` each hold a flow per AC step.
- Scenario 9: every code edit is followed by `needs` and a `build` before the next re-test; no `metro`.
- Fix-loop re-tests are one `relaunch` + `verify` per mobile surface, `verify` per web surface (after the `$CTX` restart), `replay` for backend, not one
  `step` per saved flow.
- Build scenarios: a work branch named per `$CTX` § Git & PR (default `<branch_prefix>/<KEY>-<slug>`)
  exists from Preflight; `state.md` starts with the `SKILL=` / `W=` / `CTX=` lines and has `mode:`;
  scenario 3: work dir is `<TICKET>-qa`, no branch created.
- Every edit the run made to the context file is logged `applied` in `$W/context-updates.md`; learned
  facts are logged `proposed` and not in the file; the context file is never staged.
- `plan.md` has **Automated checks** (new tests, every CI check with its Preflight baseline, CI-only
  list) and the Coverage table has an "Automated test" column; `state.md` records the gate baseline.
- `analysis.md` § Design has a Links row per design link; an unreadable one is a plan-gate question.
- A state reached with a test-data helper was preceded by one question to the user; TEMPTEST forcing
  only for states no helper reaches.
- No secret (token, password) in any file under `$W`.
- UI scenarios past the gate: `state.md` § Visual has a row per design frame in the test plan, each
  with a `-vs-design.png`; every MISMATCH is a FAIL (build) or a finding (test-only).
- The plan-approval AskUserQuestion carries the plan in the Approve option's `preview` (intent,
  steps/test plan, coverage %) — not only in chat text before the dialog.
- Test-only with a FAIL: each finding starts with an "In short: You do … You see … You should see …"
  line and has `$W/subbug-F<n>.md`; `.claude/work/qa-log.md` gained one line for the run.
- `$CTX` has `qa_share` → the report is shared there without a share question (announced in chat).
- Mobile runs: `needs` is called in Preflight; `setup`/`build` run only when it says NEEDED, started
  in the background before Phase 1 (the gate baseline after `setup`); a JS-only ticket on an
  unchanged native fingerprint has no `build` call; `metro` is started without `reset` unless the
  branch or dependencies changed.
- Scenario 10: no question asked; `analysis.md` / `state.md` log each `auto:` decision and the PR lists them;
  `state.md` has `approved: automatic`; a PASS opens a ready PR, CONCERNS/FAIL a draft one; no shared-env
  write without `automatic_shared_writes: yes`; `$W/result.json` has every key, `status` and `pr` filled.
- Scenario 11: `state.md` § PR comments has one line per open comment from `pr_comments.py list`; the
  bug is `patch`, the question `answer` (with `file:line`), the outside-the-ACs request `intent-gap`
  (a question at the gate, not a code change), the pushback `reject` with evidence; the gate shows a
  draft reply for each `reject` / `defer` / `answer` / `intent-gap` item; the earlier run's `$W` is kept, not moved aside.
- A ticket adding interactive UI: `shots/<surface>/a11y-<state>.txt` exists for each new interactive
  state on each UI surface, and a violation on a changed element was fixed or is in Review's findings.
- Re-running a shipped ticket (with or without `--automatic`) reuses its branch and PR: no second
  branch or PR, the developer's pushed commits kept, and the gate baseline taken on the merge-base.
- An AC accepted at Test's 3-attempt cap is in `state.md` § Waivers, the verdict is WAIVED (or CONCERNS
  listing the waiver, when a concern also applies), and Ship asks no second waiver question.
- Mobile steps go through the Maestro session (`MAESTRO EXIT` lines from the driver, steps run by
  `maestro_session.py`, no per-step `maestro test`); forced states use the driver's `force`; React Native: `index.js` has no
  `TEMPTEST quiet` line at the leftover check or at Ship.
