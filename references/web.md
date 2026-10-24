# Web surface — Playwright driver (`drivers/web/web.sh`)

Generic facts about the web driver; the app's URL, start command, login policy and known pages live
in the repo's project context (`.claude/project-context.md`, else the § Project context of
`AGENTS.md` / `CLAUDE.md`; § Test surfaces, § App knowledge).
Pass `WEB_OUT=$W/shots/web` (`$W` = the run's work dir, `SKILL.md` § Paths and surfaces — `<TICKET>-qa` in `--test-only`) in front of every call (shell variables don't
survive between tool calls; the driver refuses to run without it). `web.sh help` prints the usage.

| Need | Command |
|---|---|
| install the driver (once per machine) | `web.sh setup` — Playwright 1.56.1, ffmpeg-static and axe-core 4.10.2 in `~/.cache/product-engineer/web` |
| URL reachable, driver, saved login | `web.sh status` |
| start the app locally (`WEB_START_CMD`) and wait for it | `web.sh start` |
| log in once, by hand, in a real window | `web.sh login` — the user logs in, closes the window; the session is saved once per repo (`.claude/work/.web/auth.json`, or `WEB_AUTH_FILE`) and reused by every step of every ticket until it expires. Passwords never pass through the skill |
| roles and names on a page, to write locators | `web.sh inspect [path]` — the accessibility tree (`- button "Add item"`) |
| one test step | `web.sh step '<playwright test body>' [ac<N>-<k>-<state> \| look-<x>]` |
| a look at a state a step reached (visual check) | end that `look-<state>` step with `await page.screenshot({ path: '<WEB_OUT>/look-<state>.png' })` — `shot` opens a fresh page at a path |
| page screenshot | `web.sh shot <name> [path]` |
| accessibility of a state a step reached | end that step with `await a11y('<state>', '<css scope>')` — axe-core (`WEB_A11Y_TAGS`, default WCAG 2.1 A + AA) on the page as it is; `<impact> <rule> — <help> — <n>: <targets>` lines in `a11y-<state>.txt`, listed, never failing the step; a step that fails later discards them. A scope that matches nothing, a tag no axe rule has, or (the command) a page that isn't HTTP 2xx fails it. A page with no interaction: `web.sh a11y <name> [path] [css scope]` (~2 s). axe is evaluated, so a page's CSP can't block it |
| re-check every saved flow (the fix loop) | `web.sh verify` — one call, no recording |
| evidence run | `web.sh replay` |
| join the step clips into one video | `web.sh video <name> [clip-filter]` |

## Writing steps
- A step is the body of a Playwright test: it gets `page`, `expect`, `baseURL`. Each step runs in a
  fresh page — **steps don't share state**: start every step with `await page.goto('<path>')`
  (relative to `WEB_URL`) and do the whole AC state in one step.
- Pass the body as a quoted heredoc, so its own quotes need no escaping (the examples here use `'`):
  `web.sh step "$(cat <<'JS'` … body lines … `JS` `)" ac1-1-list` — one line per statement.
- **Forced states** (`phases/test.md` §3) have no `force` command on web: add the TEMPTEST lines,
  reload the app, run a step named `ac<N>-<k>-<state>-forced` (never saved) ending with
  `await page.screenshot({ path: '<abs $W>/shots/web/ac<N>-<k>-<state>-forced.png' })`, then remove the
  forcing. No forced-state video on web — Ship leaves a video field unset and says so.
- Prefer role/text locators (`getByRole('button', { name: 'Search' })`, `getByText('No results
  found')`, `getByPlaceholder`) over CSS; they double as accessibility checks. On a page you haven't
  seen yet, `inspect` it first and take roles and names from its output — don't guess them.
- Every step watches the page: an uncaught JS error **fails the step** even when its `expect`s pass;
  console errors and HTTP 5xx responses are listed in `<name>-errors.log` without failing it — read
  them, they are often the bug. When the AC itself expects an error, call `allowPageErrors()` first in
  the body.
- Prove outcomes with `expect(...)` (`toBeVisible`, `toHaveText`, `toHaveURL`, `toBeDisabled`); a
  failing step saves `fail-<name>.png`.
- Network-level checks: `page.waitForResponse(r => r.url().includes('/graphql') && r.ok())`, or
  check the server side on the `backend` surface.
- Steps named `ac*` that pass are saved to `flows/<name>.spec.mjs`; `look-*`/unnamed are diagnostics.

## Recording
- `replay` runs each saved flow on its own (AC order), with Playwright video on and actions slowed
  (`WEB_SLOWMO`, default 600 ms) so a reviewer can follow; videos are converted to mp4
  (ffmpeg-static; Homebrew ffmpeg not needed) and joined into `workflow.mp4` + `ac<N>.mp4`.
- Fast flows still make short clips: end a step with an `expect` on the result state so the final
  frame shows it.

## Verified
- 2026-10-24, Playwright 1.56.1 + axe-core 4.10.2 on a local fixture page under `script-src 'self'`:
  `a11y` finds a missing alt, an unnamed button and an unlabeled input (scoped to a dialog); a clean
  scope says "no violations"; a scope matching nothing, a misspelt tag and a 404 each fail; a step
  failing after its `a11y()` leaves no `a11y-*` file; `verify` re-runs a flow with `a11y()`.
- 2026-10-21, against a local fixture page: an uncaught error fails a step whose `expect`s pass,
  `allowPageErrors()` lets it pass; console errors and 5xx land in `<name>-errors.log` without failing;
  a clean re-run removes the old log and a passing step its old `fail-<name>.png`; `inspect` prints the
  accessibility tree, also on a page that throws; `shot` writes `shot-<name>-errors.log`.

2026-10-17:
- Chromium 1194 was already cached (`~/Library/Caches/ms-playwright`) → Playwright 1.56.1 runs
  without downloading; other versions download their own browser.
- Specs import `@playwright/test` from the driver install through a `node_modules` symlink in the
  evidence folder (ESM ignores NODE_PATH).
- example.com and similar documentation domains ask not to be used for testing — test against the
  real app or a local fixture page.
