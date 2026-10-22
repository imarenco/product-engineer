# Automatic mode (`--automatic`)

For pipelines: one run, no human, from the ticket to the PR. Read it before Preflight when the
flag is given (or `state.md` `flags:` has it).

Passing the flag is the plan approval and the standing answer "take the recommended option". It
combines with every other flag, and `state.md` records it so a resume keeps it. This file
overrides every question and every "the user decides" in the phase files:
- **Never ask.** Each question gets its recommended option, logged as `auto: <question> → <answer>` in
  `analysis.md` § Clarifications (up to the plan) or `state.md` § Auto decisions (after it), and listed
  under "Decided automatically" in the PR (`--test-only`: in `report.md`). The plan gate writes
  `plan.md` and records `approved: automatic` — no dialog. Where a phase gives no recommendation: no
  design found → compare against the existing app (`providers/design/none.md`), as an assumption; a
  tracker field that holds one video → the first tested surface's; a design link that can't be read
  → no design for those states, compared like "no design found", listed as a concern; a design DELTA
  that isn't obvious → kept and listed as a concern.
- **Moving on.** An AC still FAIL after the fix cap, and every BLOCKED or HUMAN AC, counts as accepted
  for moving on to Review, Evidence and Ship — the verdict carries it. A review finding still open
  after the last round is deferred and listed as a concern — a critical one keeps the verdict at FAIL.
- **Stop instead** when no option is safe to take alone: there is no project context, or it lacks a
  value the repo can't show (tracker, provider config, base-branch rule); the tracker can't be read; tracked changes are already
  in the tree; the branch check fails; the work branch can't be brought up to date with origin (Preflight step 4, Ship §6); an AC or the plan turns out wrong (`phases/test.md` §4); or the
  recommended answer would cross the plan's Intent / Never or a safety rule (including a behaviour
  change the plan didn't foresee, `phases/code.md` § How to work, step 4). A stop pushes nothing: `$W/report.md` says why
  and what a human must do, `state.md` gets `phase: stopped` and `stopped: <reason>`, and
  `result.json` is written.
- **The project context is never written.** A value found during the run (a CI check list, a driver
  value) is used for this run and logged `proposed` in `$W/context-updates.md`, never applied.
- **Surfaces**: one that can't be reached gets one diagnosis-and-retry round (rebuild, reboot,
  restart) — the "keep trying" recommendation doesn't apply — then its ACs are BLOCKED. A background
  build or setup that fails: the same. A device or browser that isn't logged in → its UI ACs are
  BLOCKED.
- **Shared environments**: writes to staging, a shared DB or queue, and test-data helpers, only when
  `$CTX` § Test surfaces says `automatic_shared_writes: yes`; otherwise those ACs are BLOCKED, and
  the backend replay on a non-local target runs without its reset (`BACKEND_RESET_CMD= API_RESET_CMD=
  backend.sh replay`). Production never.
- **Fix cap** (`phases/test.md` §4): after 3 failed attempts, one "rethink the approach" round of up to
  3 more; still failing → it stays FAIL. No waivers — only a human waives.
- **Review**: an `intent-gap` / `bad-plan` finding is triaged `defer` and listed as a concern.
- **Ship**: PASS or WAIVED → the PR, ready for review (an existing draft is marked ready), and the
  tracker fields. CONCERNS or FAIL → a **draft** PR (`gh pr create --draft`; a PR that already exists
  is updated and turned back into a draft, `phases/ship.md` §6) with the verdict and every concern and failure at the top; no tracker
  done-fields, transitions or comments. A tracker field that already holds a value is left as is.
  With `--no-sim`, or an agent without subagents, the verdict is CONCERNS at best — the PR is always a
  draft. `--test-only`: shared per `qa_share`, else kept local.
- **Last**, on every exit — Ship §8, QA report §4 (after its `qa-log.md` line), or a stop in any phase:
  `$W/result.json` —
  `{"ticket", "mode": "build" | "test-only", "status": "done" | "stopped", "verdict": "PASS" |
  "WAIVED" | "CONCERNS" | "FAIL" | null (before Review), "pr": <url> | null, "draft": <bool>, "branch": <name> |
  null, "report": <path>, "auto_decisions": <count>, "reason": <why it stopped> | null}` — the file
  a pipeline reads. `--test-only`: `pr` is the PR under test (or null), `draft` is null and `branch`
  is the branch tested — the run changed neither.
