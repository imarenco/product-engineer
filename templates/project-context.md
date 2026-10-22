# Project context — <repo> (<company>)

Read by skills (e.g. `product-engineer`) to learn how this repo and company work. Generic
skills hold the method; this file holds every fact specific to this project. Keep it current: a run that
learns a project fact the hard way proposes one dated line for the matching section (in its work dir's
`context-updates.md`), applied with the user's OK.
Unknown values: write `TODO (ask)` — the skill asks the user and fills them in. Sections marked
"runs add to this" start empty.

## Project
Filled from the repo (package.json / build files / AGENTS.md / CLAUDE.md / `git remote`):
- What the app is; stack and version (e.g. React Native 0.81 + TS / Swift / Kotlin / web React);
  platforms (iOS, Android, web).
- Convention docs that are law (AGENTS.md, CLAUDE.md, docs/…).
- Code layout: where screens, components, hooks, pure logic, services, theme/tokens and assets live.
- Data layer (GraphQL/REST, codegen flow, schema location), local storage, logging rules.
- Related repos and how to look things up across them.

## Commands
Filled from package.json scripts / Makefile / CI config:
| Purpose | Command | Notes |
|---|---|---|
| install deps | | |
| unit tests | | |
| integration tests | | backend: prerequisites (DB/container up, env file, migrations run) |
| lint | | known noise that is not a real error |
| format check | | check-only (`--check` / `--list-different`) — the gate must not rewrite files; the write form goes in Notes |
| typecheck | | pre-existing error backlog? → compare totals with a baseline |
| forbidden patterns | | e.g. no console.log |

CI checks every PR must pass (workflow file → command → scope → when it runs), so the skill runs the
same before opening the PR; mark the ones that can't run locally.

## Code conventions (beyond the docs)
- Imports, file naming, where tests go and which code gets unit tests, style reference spec.

## Tracker
provider: **<jira | linear | github-issues | none | …>**
| Key | Value |
|---|---|
One row per key in the provider's "Config keys" table (`providers/tracker/<name>.md` in the skill),
plus the two the skill itself reads:
- `qa_share` — where a `--test-only` QA report goes without asking (`ticket comment` / `pr comment` /
  `local`); unset → ask.
- `domain_skills` — skills that map an area of the product (payments, search…), read in Phase 1.
- `bug_types` (optional) — issue types that are bugs, when `branch_prefix` → `fix` isn't the rule.

## Design
provider: **<figma | none | …>**
| Key | Value |
|---|---|
One row per key in the provider's "Config keys" table (`providers/design/<name>.md` in the skill).
`quirks`: runs add to this.

## Git & PR
- Base branch rule (main / a release branch per fix version / …), how to update it.
- Branch and commit naming (overrides the skill's default `<feat|fix>/<KEY>-<slug>`); PR command,
  labels, assignee; PR house style (example PR number).
- Where PR evidence media goes (e.g. an orphan `pr-assets/<KEY>` branch).
- Files never to stage (local junk, local hacks, files builds touch incidentally).
- Reviewers: a local, read-only review skill or command to run in the Review phase (optional); where a
  review post goes (a channel) — only offered at Ship.

## Test surfaces
How ACs get exercised in this repo. Keep only the rows that apply; the skill offers these at Preflight.
| Surface | Use for | Driver | Notes |
|---|---|---|---|
| `ios` / `android` | mobile UI ACs | per `MOBILE_DRIVER`: react-native, or native ios / android (Maestro) | device names, which one is logged in |
| `web` | web UI ACs | web (Playwright) | local or deployed URL, login policy |
| `backend` | backend ACs: API responses, GraphQL fields, DB rows, queue messages, jobs | backend (curl/jq, DB_CMD, CLI probes) | environment, auth source, read-only DB? |
| `<name>` | e.g. end-to-end on a preview env | external: skill `<plugin:skill>` or a command | how to run it, where its report/videos land |
Never point a surface at production unless it is explicitly read-only.

Driver values (sourced as shell; `$UDID`, `$SERIAL`, `$REPO` are set by the drivers). Keep only the
surfaces you use:
```env
# mobile
MOBILE_DRIVER=       # react-native (package.json depends on react-native) | native — read by the skill to pick the driver
APP_ID=              # bundle id / applicationId
IOS_DEVICE=""        # simulator by name, e.g. "iPhone 15" (the same on every machine); unset = a booted one
IOS_RUNTIME=         # optional iOS version for IOS_DEVICE, e.g. 26.1; unset = the newest
ANDROID_AVD=         # emulator by AVD name (emulator -list-avds); unset = the running emulator / first AVD
# IOS_UDID=          # one machine only: a simulator's UDID, wins over IOS_DEVICE (or pass SIM_UDID on the call)
SETUP_CMD=""         # install deps (npm ci, pod install…), run from the repo root; unset = none
IOS_BUILD_CMD=''     # builds and installs on $UDID
ANDROID_BUILD_CMD='' # builds and installs on $SERIAL
ANDROID_APK=         # path of the built APK, for manual installs
# react-native only
METRO_PORT=          # bundler port; unset = no bundler
IOS_STATE_FILE=      # app-state (MMKV) file inside the app container, for `mmkv`
ANDROID_STATE_FILE=  # same, read with run-as
# web
WEB_URL=             # app base URL
WEB_START_CMD=""     # starts the app locally; unset = it runs elsewhere
# backend
API_URL=             # HTTP API base URL
API_AUTH_CMD=''      # prints one header line ("Authorization: Bearer …"); never a stored secret
DB_CMD=''            # reads SQL on stdin (e.g. psql …); confirm before writes to a shared DB
BACKEND_RESET_CMD='' # resets test data before a replay
# optional, driver defaults: WEB_READY_URL=$WEB_URL WEB_VIEWPORT_W=1280 WEB_VIEWPORT_H=800
#   WEB_SLOWMO=600 API_GRAPHQL_PATH=/graphql
```
Surface notes — runs add to this: devices to avoid, signing for local builds, how to probe app state
and read logs, seeded users and login-only pages, how to get a token or reach the DB (tunnels), and
backend probes for `sql` / `cmd` steps (queries, queue and job commands, cache keys, log queries that
show state the API doesn't return, with what "right" looks like).

## App knowledge for testing
Runs add to this: login/accounts policy (never store passwords) and environments; navigation (deep
links, reference tap points per platform); quirks that break automation (dev toasts, permission
dialogs, hot reload); what can't be tested on a simulator (→ HUMAN); test-data helpers (what they
write, preconditions — preferred over forcing code).

## People & process
- Who the user is and their standing preferences; who reviews; who can't open which links.
