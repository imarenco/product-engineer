# Resume — continuing a run

Read it before Preflight when the args say `resume`, or when `$W/state.md` exists.

- **Which run.** `resume` finds it by its folder, `.claude/work/<TICKET>/` or `<TICKET>-qa/` (both
  exist → the more recently changed one, said in chat), and takes its flags from `state.md`
  `flags:`; flags given with `resume` override them.
- **Finished runs aren't resumed.** A `state.md` with `phase: done` or `phase: stopped`, without
  `resume` (or `--pr-comments`, which continues a done run: `modes/pr-comments.md`), is a finished run: move its folder aside (`$W` → `$W.<YYYYMMDD-HHMM>`, its evidence stays
  there) and start a new run at Preflight — a re-test after the developer's fixes is a new run, never
  the old SHA. Resuming a stopped run asks again (it runs interactively unless `--automatic` is given
  again: rewrite `flags:` without it, so a compaction can't bring it back; delete the stale
  `result.json`); it picks up at the phase in `stopped:`; a stop for a wrong AC or plan resumes at the plan gate.
- **Preflight on resume**: only steps 1 (context only — `state.md` is kept, with `resumed: <time>`
  added; add the path lines if an older one lacks them), 2, 3 and 6 (providers, git status, surface status) — plus, past Phase 2, the
  design provider (`phases/design.md`, top). Never re-check out the
  base; stay on the work branch `state.md` names (test-only: the SHA it names). In step 3 the run's
  own uncommitted changes are expected: check the branch, and that every changed file is explained by
  `plan.md` — ask only about files that aren't. Before the plan exists any tracked change is a
  question. In both modes, a file whose only change is TEMPTEST lines (forcing, `rn.sh quiet`) and
  the context file are expected.
- **Where to pick up**: the phase `state.md` names, at its first unfinished step — not from its top.
  In Test: re-run the `phases/test.md` §2 gates (the session is new, so no gate result is current),
  then go to `phases/test.md` §4 for each AC that is FAIL in `state.md` § Verdicts, using § Attempts
  (what was tried, the failing step's command) instead of starting over; PASS ACs are re-checked by
  `verify` (backend: `replay`; §4 step 5), not re-tested by hand; `PENDING (…)` ACs (a plan change, a PR round) are
  tested again from the test plan (§3), and a `replan:` line means that Review round is still owed.
  `--test-only`: no §4 — its FAILs are already findings; carry on with the next unchecked AC. A
  compacted session (not a new one) picks up the same way.
- **Old runs**: a `state.md` that names an `api` surface is from before the rename — treat it as
  `backend` and move `$W/shots/api` to `$W/shots/backend`.
