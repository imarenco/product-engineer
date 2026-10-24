# Test-only mode (`--test-only`)

The feature is already developed: you verify it, you don't build it. Same phases; each phase file
names its own `--test-only` differences, and these live here. Read it before Preflight.

- **Preflight**: work dir `W=<repo root>/.claude/work/<TICKET>-qa` (a build run's `$W` stays untouched);
  `mode: test-only` in `state.md`. Step 4 only resolves the base branch by its rule (Test compares
  failing checks against it) — no checkout, no new branch. Find the code under test:
  `gh pr list --state all --search "<TICKET>"` and `git branch -a | grep -i <TICKET>`; one question
  to pick it (the ticket's PR branch / current branch / base branch if already merged). Clean tree
  (the context file excepted — `SKILL.md` § Rules for every phase), then
  `git fetch origin && git checkout -m --detach origin/<branch>` (or the local branch when it has no
  remote or is ahead of it — `git rev-list --count origin/<branch>..<branch>` > 0 — said with its SHA;
  same conflict rule as step 4). Record branch + SHA in `state.md`, and the branch you started on. No gate baseline
  (step 7): Test compares against the base instead.
- **Plan gate**: the plan is only the **Test plan**, **Automated checks** (the existing suite + each CI
  check, no new tests), the **Coverage** table (AC ↔ test rows, no Steps column; coverage % = ACs with
  a test row / all ACs) and Out of scope. Same questions-then-approval gate; the approval is to start
  testing.
- **Code: skipped** — never edit product code; temporary `// TEMPTEST` forcing is allowed and
  reverted.
- **Test** (`phases/test.md`): no new unit tests — run `phases/test.md` §2 with the plan's Automated checks
  once and note the results for the report, then go to `phases/test.md` §3. A failing check is a finding only if its failing tests
  don't fail on the base too (compare the failing test ids, not the check's status) — in this order: the base's latest CI run
  (`gh run list --branch <base> --limit 3`; `gh pr checks <N>` only shows this PR's own checks); else
  one run in a temporary worktree (`git worktree add <scratch dir> $(git merge-base origin/<base>
  HEAD)`, the install command first, `git worktree remove` after) — never by checking out the base
  here: it breaks the branch check.
- **No fix loop** (`phases/test.md` §4): a FAIL is re-run once (flaky driver / env), then recorded in
  `state.md` § Findings for `phases/qa-report.md` — steps to reproduce, expected vs actual, evidence,
  likely `file:line` — and you move on to the next AC. Never edit product code. A red AC is a finding
  for the report, not a blocker for the next phase.
- **Review**: only the refuter, challenging both PASS and FAIL verdicts (`phases/review.md` §2).
- **Evidence**: replay the passing ACs; failing ACs keep their `fail-*.png` as evidence
  (`phases/evidence.md`).
- **Ship**: `phases/qa-report.md` instead of `phases/ship.md` — no work branch, commit or PR, nothing of
  the code pushed; only the share option the user picks may publish media (the assets branch).
