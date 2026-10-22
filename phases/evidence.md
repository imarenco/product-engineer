# Phase 7 — Re-test with screenshots and recording (evidence)

Goal: once every AC passed in the Test phase, replay all of them on the final code, on every surface
used — capturing screenshots and recordings (mobile, web) or request/command transcripts (backend) —
ready to publish. Nothing is debugged here — a failure sends you
back to `phases/test.md`. Skipped with `--no-sim` (then Ship has no media; a QA report says no AC was
verified on a surface).

`--test-only`: replay the passing ACs; failing ACs keep their `fail-*.png` as evidence. Nothing is
published until the share decision in `phases/qa-report.md`.

## 1. Preconditions
- Review done (`phases/review.md`): findings triaged, verdict written. Every AC PASS, or the user
  accepted the rest (`--test-only`: failing ACs are findings; `--automatic`: moved on, `modes/automatic.md`).
- The leftover check passes (`SKILL.md` § Rules for every phase) — the replay must run on the code that will be
  committed.
- Only PASS ACs are replayed. ACs that are FAIL (accepted after the cap, or waived), BLOCKED or HUMAN
  are not: delete their flows if they have any (a flow saved before the AC broke would replay as a
  regression) — their Test `fail-*` shots and notes are their evidence.
- Per surface, `ls $W/shots/<surface>/flows`: one flow per step of every PASS AC, named
  `ac<N>-<k>-<state>`. Delete flows of renamed or abandoned steps (and flows that only work with
  forcing); a PASS AC's missing step means it was never saved — re-run it in Test. After deleting a flow, check the next one still
  starts where it expects: a deleted "go back" step once left every later flow on the wrong screen.

## 2. Replay — once per surface tested
```
export SIM_PLATFORM=ios     SIM_OUT=$W/shots/ios;     <ios driver> relaunch && <ios driver> replay
export SIM_PLATFORM=android SIM_OUT=$W/shots/android; <android driver> relaunch && <android driver> replay
WEB_OUT=$W/shots/web  $SKILL/drivers/web/web.sh replay
BACKEND_OUT=$W/shots/backend  $SKILL/drivers/backend/backend.sh replay   # runs BACKEND_RESET_CMD first when set
```
Only surfaces with at least one PASS AC are replayed. A surface whose ACs are all FAIL, BLOCKED or
HUMAN has nothing to replay (its driver would stop with "no saved flows"): skip it, and write
`<surface>: no replay — <why>` in `state.md`; the report and PR say so.
The mobile driver per `MOBILE_DRIVER`: `references/mobile.md` § Which driver. One line per tool call,
literal paths (a `VAR=x cmd1 && cmd2` prefix reaches only `cmd1`). Each replay takes minutes: a
**background run** (`SKILL.md` § Agent tools); web and backend can run alongside the mobile one (iOS
and Android share one Maestro session: keep those two one after the other). Before a mobile replay —
React Native: `quiet on` + `relaunch` (`references/react-native.md` § Test); native: `needs`, then
`build` if NEEDED (`references/mobile.md` § Native apps). The replay re-runs every saved flow in AC
order — the regression check on the final code — and writes `ac<N>-<k>-<state>.png`, `workflow.mp4`
and `ac<N>.mp4` (UI) or the transcripts and `backend-evidence.md` (backend); it ends with
`REPLAY: all steps passed` or the failing steps. External surfaces: run the named skill's recorded
run and copy its outputs here.
- A failing step = regression → back to Test (root cause, fix, re-verify), then one Review round on
  that change (`phases/review.md` §4), then Evidence again from §1. `--test-only`: a finding in
  `state.md` § Findings instead (no loop back).
- Driver noise (an iOS driver timeout while the screenshot shows the right state) → rerun the replay.

## 3. Check the evidence
- Per row of state.md § Visual whose AC is PASS: `$SKILL/scripts/media.sh compare $W/design/<frame>.png
  $W/shots/<surface>/<its ac step>.png` (a forced state: its `-forced` shot, in `shots/<surface>/` or
  `forced/`) → `<its ac step>-vs-design.png` beside it (published with the other `ac*` shots). Read each: still MATCH/DELTA as in Test — a new MISMATCH is a regression, handled
  like a failing step above (`--test-only`: a finding).
- Check each `workflow.mp4` isn't blank: `$SKILL/scripts/media.sh frame <video> 5`, check the PNG (image check).
- Backend: read `backend-evidence.md` — every block PASS, no secret in it.
- Forced-state shots and videos from Test are part of the evidence too.

Done when the replay passed on every surface that has a PASS AC and the evidence was checked (each
such UI surface has its own `shots/<surface>/workflow.mp4`; backend has
`shots/backend/backend-evidence.md`; a skipped surface has its `no replay` line). Nothing is published here — that is the last phase, after the verdict
gate. Next: `phases/ship.md` (`phases/qa-report.md` in `--test-only`).
