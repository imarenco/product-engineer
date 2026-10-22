# Backend surface — `drivers/backend/backend.sh`

For ACs whose behaviour is behind the UI: an API's response, a GraphQL field, a row written to the
database, a message on a queue, a job's effect, a cache entry. The API base URL, auth, database access,
probe commands and reset command live in the repo's project context (`.claude/project-context.md`,
else the § Project context of `AGENTS.md` / `CLAUDE.md`; § Test surfaces). Pass
`BACKEND_OUT=$W/shots/backend` (`$W` = the run's work dir, `SKILL.md` § Paths and surfaces —
`<TICKET>-qa` in `--test-only`) in front of every call; the driver refuses to run without it.
`backend.sh help` prints the usage.

| Need | Command |
|---|---|
| URL reachable, auth, DB and reset configured | `backend.sh status` (requests time out after `API_TIMEOUT` seconds, default 60) |
| REST call + assertion | `backend.sh call <name> <METHOD> <path> [json-body] [jq-assert]` |
| GraphQL + assertion | `backend.sh gql <name> '<query>' [variables-json] [jq-assert]` |
| database check | `backend.sh sql <name> '<SQL>' [regex-assert]` |
| any other backend system (queue, job runner, cache, logs) | `backend.sh cmd <name> '<command>' [regex-assert]` |
| evidence run | `backend.sh replay` (runs `BACKEND_RESET_CMD` first when set) |
| paste-ready evidence | `backend.sh report` → `backend-evidence.md` (one collapsible block per step) |

## Rules
- A step passes on HTTP 2xx and, when given, the `jq` expression evaluating to `true`
  (`'.data.review.activeDays == 7'`, `'.items | length > 0'`). GraphQL errors (HTTP 200 with
  `errors`) fail. `sql` and `cmd` steps pass when the command exits 0 and the output matches the regex.
- Every step writes `<name>.txt`: request or command, status, output (pretty JSON, first 200 lines),
  assertion and verdict. That transcript is the backend evidence — there is no video.
- `API_AUTH_CMD` prints one header line; it is called per request, reaches curl as config on stdin
  (not in `ps`), and is **never written** to transcripts or saved flows. Tokens come from a command (a
  login script, `gcloud auth print-identity-token`, a token file) — never paste secrets into the
  context or steps. A `cmd` step's command **is** written to its transcript: it reads credentials from
  the environment or a token command, never inline. A failing `API_AUTH_CMD` fails the step
  (`(API_AUTH_CMD failed)`): no request goes out without the auth it was meant to carry.
- Prove the effect, not just the response: after a write, read it back (`gql`/`call`), check the row
  (`sql`), or check what it queued (`cmd`). Read-only DB roles where the project has them.
- `cmd` probes come from `$CTX` § Test surfaces (backend probes): the project's own CLI for its queue
  (message count, peek), its job runner (job status), its cache (a key's value), its logs. Prefer
  read-only commands (peek, count, get) to ones that consume or change state (pull, ack, delete) —
  a consuming probe changes what the system under test sees.
- Async effects (a job, a consumer) can lag the request: assert on the final state, and say in the test
  plan how long it may take.
- Steps that create data replay cleanly only from the same starting state: set `BACKEND_RESET_CMD`
  (re-seed a test DB, purge a test queue, restart a local service) or write assertions that hold on a
  repeat (`.id != null`, `length >= 1`). Verified 2026-10-17: without either, a create-then-count flow
  fails its replay. `API_RESET_CMD`, the old name, still works.
- Never run steps against production unless the context explicitly says that surface is read-only
  production access. Any non-local target (staging, a shared DB, a shared queue) → confirm with the
  user at Preflight before the first write or seed.
- **Backend bugs**: reproduce before fixing — the bug's Current line as a step named `repro-<n>` that
  fails on the unfixed code (`call`/`gql` asserting the right result, `sql` on the wrong row, `cmd` on
  the wrong queue state). It is never saved as a flow; its transcript `repro-<n>.txt` stays for the
  PR's root-cause note. After the fix the same check runs as an `ac<N>-…` step and passes.
- Values given on the command line (`API_URL=… backend.sh …`) override the context for that call but
  are not saved in the flow: the replay uses the context's values.
- Backend unit/integration tests are separate: run them from `$CTX` § Commands (e.g. an
  `integration tests` command) in the Test phase gates.

## Verified
- 2026-10-17 (as `api.sh`), against a local fake API + SQLite: PASS/FAIL per assertion, GraphQL errors
  fail, only passing `ac*` steps are saved, no auth token in any transcript, replay + report work.
  macOS bash 3.2 treats empty arrays and missing optional args as unbound under `set -u` (the script
  guards both). Also: the auth header arrives; 404, connection refused (HTTP 000) and a false
  assertion each FAIL with the reason; a failing reset command stops the replay; the report lists only
  saved flows.
- 2026-10-21 (renamed `backend.sh`, `cmd` added): the same checks pass; `cmd` passes on exit 0 + regex,
  fails on a non-zero exit or no match; flows saved by `api.sh` still replay; `API_RESET_CMD` still
  runs. An API that echoes the auth header in its response body puts the token in the transcript —
  the driver can't redact what the server returns, so read `backend-evidence.md` before publishing.
  A failing `API_AUTH_CMD` (`false`) fails the step; with a working one and with none, the step passes.
