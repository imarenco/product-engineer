# product-engineer

**A skill for AI coding agents that takes a ticket from your tracker to a reviewed, tested pull
request — and waits for your approval before it writes any code.**

Works with **Claude Code, Cursor and GitHub Copilot**. It's written in the open
[Agent Skills](https://agentskills.io) format (`SKILL.md`), so you install it once as a folder and
your agent picks it up.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)
![Agent Skills](https://img.shields.io/badge/Agent%20Skills-SKILL.md-orange.svg)
![Agents: Claude Code · Cursor · GitHub Copilot](https://img.shields.io/badge/agents-Claude%20Code%20%C2%B7%20Cursor%20%C2%B7%20Copilot-555.svg)

Give your agent a ticket key. It then works the way a careful product engineer would:

- reads the ticket, its comments, linked tickets and the design
- rewrites every acceptance criterion (AC) so it can be tested
- writes a plan and **waits for your approval**
- writes the code in your repo's conventions
- proves every AC on a real iOS simulator, Android emulator, browser or backend
- has the result reviewed by independent reviewers
- records evidence: screenshots, videos, request transcripts
- opens the PR and updates the ticket

A **QA mode** (`--test-only`) checks an already-built feature against its ACs and writes a report,
without changing any code.

```
/product-engineer PROJ-123 --ios
/product-engineer PROJ-123 --test-only --web
```

## Contents

- [Quick start](#quick-start)
- [How a run works](#how-a-run-works)
- [Safety: what it does without asking](#safety-what-it-does-without-asking)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Running in a pipeline](#running-in-a-pipeline)
- [Configuration](#configuration)
- [Supported tools](#supported-tools)
- [Compatibility](#compatibility)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [Project structure](#project-structure)
- [Contributing](#contributing)
- [License](#license)

## Quick start

1. Clone the skill into your agent's skills folder ([all options](#installation)). For Claude Code
   and Cursor, one folder serves both:
   ```sh
   git clone https://github.com/imarenco/product-engineer.git ~/.claude/skills/product-engineer
   ```
2. Open your agent in the repo you work on and run the skill — `/product-engineer PROJ-123`, or just
   ask: "implement PROJ-123".

3. Answer the setup questions. On the first run the skill drafts the repo's
   [project context](#configuration) from what it finds (commands, CI, devices) and asks only for
   what it can't: your tracker, design tool, base-branch rule and PR conventions. Commit that file
   on its own so your team shares it.

From then on, a run stops for you at the plan, and whenever something needs a decision.

## How a run works

| # | Phase | What happens | You're asked when… |
|---|---|---|---|
| 0 | Preflight | Loads the project context, creates a work branch from the fresh remote base, starts slow builds in the background, records a baseline of the repo's checks | something is unclear or already broken; which surfaces to test (no flag given); before the first write to a shared test environment |
| 1 | Ticket | Reads the ticket, epic, comments, linked tickets and media; rewrites each AC in a testable form with a priority | an AC is ambiguous |
| 2 | Design | Finds the design frames and maps them to the repo's tokens, icons and components | a design link can't be read |
| 3 | **Plan gate** | Steps, test plan, CI checks, AC coverage %, out of scope, assumptions | **always — no approval, no code** |
| 4 | Code | Implements the plan in the repo's conventions | the change would differ from the plan |
| 5 | Test | Unit tests, the repo's CI checks run locally, every AC verified on each chosen surface, a visual check against the design; failures loop back to Code (3 attempts per AC, then you decide) | a fix keeps failing |
| 6 | Review | Independent reviewers in fresh subagents try to break the "done" claim: spec, standards, security, performance | a finding changes scope |
| 7 | Evidence | Replays every AC on the final code: screenshots and video (UI), request and command transcripts (backend) | — |
| 8 | Ship | Publishes the media, commits, pushes, opens the PR, fills the tracker fields | the verdict is CONCERNS or FAIL; before replacing a tracker field that already has a value |

The PR states a verdict (PASS, CONCERNS, WAIVED or FAIL) with one row per AC: how it was checked,
the test that keeps it green, and its evidence. Every claim in it ("tests pass", "AC works") comes
from a command run in that session on the final code.

**Where the files go.** A run's working state lives in `.claude/work/<TICKET>/` in your repo
(`<TICKET>-qa/` for QA runs): `analysis.md`, `plan.md`, `state.md` and the evidence. The skill keeps
`.claude/work/` out of git through your local exclude file, never `.gitignore`. If the session ends
or its context is compacted, `/product-engineer <TICKET> resume` continues from the phase it
stopped at.

## Safety: what it does without asking

| Action | When |
|---|---|
| Read the repo, the ticket and the design; run builds, tests, linters, simulators and browsers locally | any time |
| Create the work branch | at Preflight, from the fresh remote base — your base branch is never edited |
| Write the project context file | at Preflight, with the values you give (`.claude/project-context.md`; you commit it yourself) |
| Change the product code | only after you approve the plan (`--automatic`: the flag is the approval), and only inside it; anything the plan didn't foresee is a question (`--automatic`: the run stops) |
| Push, open the PR, publish evidence, fill tracker fields | only in the last phase, and only when the review verdict is PASS or every failure was waived by you; otherwise it asks first. With `--automatic`: a draft PR instead, and no tracker fields |
| Comment on the ticket, move its status, post to a team channel | only when you ask, or with a standing choice you saved |
| Write test data to a shared environment (staging, a shared database or queue) | only after you confirm, before the first write; production only when the context marks it read-only |

It never stages files outside the ticket, never commits the project context with the ticket, never
skips a commit hook, and never stores passwords: logins are done by you, and tokens come from a
command you configure.

**Evidence is published to an orphan branch, `pr-assets/<TICKET>`, in the same repo.** Everyone who
can read the repo can see those screenshots and videos. The skill only publishes shots of the
finished app, but check that nothing sensitive is on screen in your test data.

## Requirements

The skill runs on **macOS**: its media scripts use Swift (AVFoundation), `sips` and `xcrun`.

| For | You need |
|---|---|
| everything | Claude Code, Cursor or GitHub Copilot ([Compatibility](#compatibility)), `git`, a GitHub repo, and the [GitHub CLI](https://cli.github.com/) `gh` logged in (PRs, PR checks, publishing evidence) |
| the tracker | an MCP server or CLI for it: Jira (Atlassian MCP), Linear (MCP or an API key command), GitHub Issues (`gh`) — or none |
| the design | the Figma MCP server — or none |
| `--ios`, `--android` | [Maestro](https://maestro.mobile.dev/) (`~/.maestro/bin`), JDK 17 (any install macOS knows, or Homebrew `openjdk@17`), `python3` |
| `--ios` | Xcode with a simulator |
| `--android` | the Android SDK with an emulator (`ANDROID_HOME`, default `~/Library/Android/sdk`) |
| `--web` | Node.js; `web.sh setup` installs Playwright and Chromium once, in `~/.cache/product-engineer/web` |
| `--backend` | `curl`, `jq`, and whatever CLI your database or queue uses (`psql`, `sqlite3`, …) |

## Installation

Clone the repo into your agent's skills folder. The skill is named `product-engineer` (the `name` in
`SKILL.md`), so the command is `/product-engineer`; keep the folder name the same.

| Agent | For you, in every repo | For one repo, shared with the team (commit it) |
|---|---|---|
| Claude Code | `~/.claude/skills/product-engineer` | `.claude/skills/product-engineer` |
| Cursor | `~/.cursor/skills/product-engineer` — or the Claude Code folder, which Cursor also reads | `.cursor/skills/product-engineer` |
| GitHub Copilot | see Copilot's docs for a user-level folder | `.github/skills/product-engineer` or `.agents/skills/product-engineer` |

For example, for Claude Code and Cursor at once:
```sh
git clone https://github.com/imarenco/product-engineer.git ~/.claude/skills/product-engineer
```

To update, run `git pull` in the skill's folder. How the agents differ: [Compatibility](#compatibility).

## Usage

```
/product-engineer <TICKET> [surfaces] [options]
```

| Surface | Tests on |
|---|---|
| `--ios`, `--android`, `--both` | the iOS simulator, the Android emulator, or both |
| `--web` | a browser (Playwright) |
| `--backend` | what's behind the UI: HTTP/GraphQL calls, database rows, queues, jobs (any CLI) |
| *(none)* | the skill asks, recommending the surfaces where the ACs are visible |

Surfaces combine: `--ios --android --backend` verifies the UI ACs on both platforms and checks the
server state behind them.

| Option | Meaning |
|---|---|
| `--test-only` | QA mode: no code changes, no branch, no PR — a QA report with findings and sub-bugs |
| `--no-sim` | unit tests and CI checks only, no surface |
| `--automatic` | no human: the plan is approved and every question takes its recommended answer — for [pipelines](#running-in-a-pipeline) |
| `resume` | continue a run from where it stopped |

Examples:
```
/product-engineer PROJ-123 --ios                  # build a UI ticket, verify on iOS
/product-engineer PROJ-456 --backend              # backend ticket: API, DB and queue checks
/product-engineer PROJ-123 --test-only --both     # QA an existing feature on iOS and Android
/product-engineer PROJ-123 resume
/product-engineer PROJ-789 --web --automatic     # pipeline: no questions, ends with a PR and result.json
```

Plain requests work too: "implement PROJ-123", "QA PROJ-123", "verify the ACs of PROJ-123".

## Running in a pipeline

`--automatic` runs the whole ticket once, end to end, with nobody answering:

```
/product-engineer PROJ-123 --backend --automatic
```

- **The plan is approved by the flag**, and every question takes its recommended answer. Each one is
  logged and listed in the PR under "Decided automatically".
- **PASS opens a PR ready for review** and fills the tracker fields. **CONCERNS or FAIL opens a
  draft PR** with the verdict and every problem at the top, and leaves the tracker alone, so nothing
  looks approved that isn't.
- **It stops, and pushes nothing,** when no answer is safe to take alone: an incomplete project
  context, a dirty checkout, or a change the plan didn't foresee. `report.md` says what a human must
  do.
- **Failures are never waived** (only a person can), and test data is written to shared environments
  only if the context says `automatic_shared_writes: yes`. Production never.
- Every run ends with **`.claude/work/<TICKET>/result.json`** — `status` (`done` / `stopped`),
  `verdict`, `pr`, `draft`, `reason` — for the pipeline to read.

What the pipeline needs: the project context committed and complete; a macOS runner for the mobile
surfaces, with the simulator or emulator and any logins already set up; `gh` authenticated; the
tracker and design MCP servers configured; and the agent run headless with permission to run
commands, edit files and push (in Claude Code, `claude -p` with a permission mode that allows them).

## Configuration

The skill holds the method. Everything specific to **your** repo and team lives in one **project
context** file in that repo:

- the commands (install, tests, lint, typecheck) and the CI checks every PR must pass
- the tracker and design tool, with their ids
- the base-branch rule, branch and commit naming, PR style, files never to stage
- the test surfaces and their values: app id, devices, URLs, auth and database commands
- app knowledge the runs learn: tap points, quirks, test-data helpers

You don't have to write it: the first run drafts it and asks only what it can't find. It is looked
up in this order:

1. `.claude/project-context.md` *(recommended: it's read only when the skill runs)*
2. a `## Project context` section in `AGENTS.md`
3. the same section in `CLAUDE.md`

`PROJECT_CONTEXT=<file>` on a driver call overrides the lookup (useful for evals and worktrees).
Runs that learn a project fact the hard way propose additions to the file; they're applied only with
your OK. The full shape is in [templates/project-context.md](templates/project-context.md).

**Mobile apps** are driven through Maestro by one of two drivers, chosen by `MOBILE_DRIVER`:

- **`react-native`** handles both platforms. Code reaches the app through Metro, so a JS-only change
  needs no rebuild. It also mutes LogBox toasts and reads MMKV state.
- **`native`** has an iOS driver and an Android driver, for Swift, Kotlin or any app without a JS
  bundler. Every code change is rebuilt, and app state is read from UserDefaults or
  SharedPreferences.

**Devices** are named, not identified, so the same file works on every machine:

```
IOS_DEVICE="iPhone 15"   # unset = a simulator that's already booted
IOS_RUNTIME=26.1         # optional; unset = the newest iOS for that name
ANDROID_AVD=Pixel_8      # unset = the running emulator, or the first AVD
```

`status` on any mobile driver prints which device it picked and why.

## Supported tools

| | Supported |
|---|---|
| Agents | Claude Code, Cursor, GitHub Copilot |
| Trackers | Jira, Linear, GitHub Issues, none (the task comes in the conversation) |
| Design | Figma, none |
| Test surfaces | iOS simulator and Android emulator (React Native or native), web (Playwright), backend (HTTP, GraphQL, SQL, any CLI), or an external skill or command your context names |
| Code hosting | GitHub |

Another tracker or design tool is one file under `providers/` that implements the operations in
[providers/README.md](providers/README.md).

## Compatibility

`SKILL.md` follows the [Agent Skills](https://agentskills.io) format. It's written for the three most
used coding agents:

| Agent | Status |
|---|---|
| Claude Code | built and tested with it |
| Cursor | reads Agent Skills (also from `~/.claude/skills/`); not tested with this skill yet |
| GitHub Copilot | reads Agent Skills from `.github/skills/` or `.agents/skills/`; not tested with this skill yet |

Where to install for each: [Installation](#installation).

The drivers, scripts and project context are plain shell and markdown, so they work the same in all
three. What differs is each agent's own tools. `SKILL.md` § Agent tools names each capability once —
a question with options, a subagent, a background run, MCP tools, an image check — with the Claude
Code tool and the fallback when an agent has no equivalent. The one real loss without subagents is
the Review phase, which can't be independent; the PR then says so.

## Limitations

- **macOS only.** The media and simulator tooling has no Linux or Windows equivalent here.
- **GitHub only** for PRs, PR checks and publishing evidence.
- **The Android drivers are less tested** than iOS, web and backend: their selection and boot logic
  has only been exercised against stand-in tools.
- Gestures that Maestro can't synthesize (pans, swipes driven by a gesture library) and anything
  needing a real device, account or store build are marked **HUMAN**, not verified.
- A full run is long: builds, device runs and several review passes. Expect it to take a while and
  use a lot of tokens.

## Troubleshooting

| Message | What to do |
|---|---|
| `pick_sim: no available simulator named '…'` | Set `IOS_DEVICE` to one of the iPhones the message lists, or create that simulator in Xcode. |
| `simulator: none — set IOS_DEVICE …` | Nothing is configured and no simulator is booted: set `IOS_DEVICE`, or run the driver's `boot`. |
| `no AVD on this machine` | Create an emulator in Android Studio → Device Manager, then set `ANDROID_AVD`. |
| `maestro: missing` | Install it: `curl -Ls "https://get.maestro.mobile.dev" \| bash`. |
| `session error: the session server didn't start` | `maestro` isn't on `PATH`, or it can't start; run `maestro --version` in a terminal. |
| `browser install failed` | `web.sh setup` needs network access once to download Chromium. |
| `set SIM_OUT=… on this call` (or `WEB_OUT`, `BACKEND_OUT`) | You're calling a driver by hand: pass the evidence folder on every call. |
| `build: NEEDED` when nothing changed | A file the build fingerprints changed (e.g. `pod install` rewrote the Xcode project); building again is the safe answer. |

## Project structure

```
SKILL.md              the method: phases, loops, rules (Claude reads this first)
phases/               one file per phase, read when the run enters it
providers/            how to talk to each tracker (jira, linear, github-issues, none)
                      and design tool (figma, none)
drivers/              one CLI per test surface: react-native/rn.sh, ios/ios.sh, android/android.sh
                      (sharing maestro/core.sh), web/web.sh, backend/backend.sh
references/           manuals for each surface: commands, pitfalls, verified behaviour
scripts/              shared helpers: media (join, compare, publish), project context lookup, change checks
templates/            the project context template
evals/                scenarios and assertions to check a change to the skill
```

## Contributing

Issues and pull requests are welcome. Keep the split the skill depends on: the method goes in
`SKILL.md` and `phases/`, tool knowledge in `providers/` and `references/`, and nothing specific to
one company, repo or team anywhere — that belongs in a project context.

Before proposing a change, run the scenarios in [evals/evals.md](evals/evals.md) with the changed
skill and with the previous version, and keep the change only if it doesn't lose an assertion the old
version passed. Use real tickets from your own repo for the scenarios, and keep them fixed between
runs.

## License

[MIT](LICENSE) © 2026 Ignacio Marenco
