# Phase 3 — Plan and HUMAN GATE (never skipped)

Write `$W/plan.md` from `analysis.md`:
- **Intent** (frozen after approval): two or three lines of what the user gets, plus **Never** — the
  things this change must not do (from Unchanged lines, `$CTX` rules, the user's answers). Changing
  either after approval means asking the user again.
- **Steps** as a checklist: `- [ ] S01 [AC2,AC3] <behaviour> — <files (confirmed with ls/grep, or
  new)> — reuse: … — unit test: <which pure logic, per the repo's testing rule>`. The Code phase
  ticks them `[x]`; `resume` reads them.
- **Test plan**: per AC — priority, the surface(s) that prove it, the steps and assertions (Maestro
  flow, Playwright `expect`, backend `call`/`gql`/`sql`/`cmd` assertion), the input that would make
  each assertion fail, the design frame to compare, how the state is reached (real navigation / real
  data / seeded data / temporary forcing). Unchanged lines from bug triplets get their own rows. Note
  platform differences (texts of native sheets, back navigation). An AC no surface can check says
  why and how it will be covered.
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
  `| AC | Priority | Steps | Test-plan rows | Surface(s) | Automated test |` — every AC has a step (or is
  already done/out of scope) and a test row; and every step names an AC — a step serving no AC moves
  to Out of scope or gets a one-line reason. Show the coverage % (ACs with step + test / all ACs).
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
   the Preflight baseline — in dependency order: ask only those whose prerequisites are settled (≤4
   per call, recommended option first, worded so accepting the recommendation is one click);
   questions that depend on an answer wait for the next round. Log each answer in `analysis.md`
   § Clarifications and fold it into the plan.
2. **Approval**, in its own question: Approve / Change something / Stop. **No approval, no code.** Put
   the plan **in the question** — a question dialog hides the chat above it (Claude Code: the
   `preview` of the Approve option; the chat fallback: the message itself): intent + Never, steps,
   the test-plan table, automated checks, coverage %, assumptions and out of scope (plain text,
   ≤ ~60 lines; longer → the essentials plus "full plan: `$W/plan.md`"). Name the ticket and where the
   plan is. **Change something** → ask what, update `analysis.md` (§ Clarifications) and `plan.md`,
   then this Approval question again.
`--automatic` and `--test-only` change this gate: their mode files.

Next: `phases/code.md` (`--test-only`: `phases/test.md`).
