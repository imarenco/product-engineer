#!/usr/bin/env bash
# Web test surface: drive a browser with Playwright for AC verification, one step per call.
# Usage: web.sh <help|status|setup|start|login|inspect|step|replay|shot|video> [...]
#   step '<playwright test body>' [ac<N>-<k>-<state> | look-<x>]   body gets `page`, `expect`, `baseURL`
#     an uncaught page error fails the step (call allowPageErrors() in the body when the AC expects one);
#     console errors and HTTP 5xx are listed, not failed
#   inspect [path]   the page's accessibility tree (roles + names), to pick getByRole locators
#   WEB_OUT  evidence dir — required on every call (`help` excepted)
#   Project values (WEB_URL, WEB_START_CMD, WEB_READY_URL, WEB_VIEWPORT_W/H, WEB_SLOWMO) come from the ```env block of
#   project context (.claude/project-context.md, else the § Project context of AGENTS.md / CLAUDE.md; PROJECT_CONTEXT overrides).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MEDIA="$HERE/../../scripts/media.sh"
# shellcheck source=../../scripts/context.sh
. "$HERE/../../scripts/context.sh"
usage() { sed -n '2,/^set -uo/p' "$0" | sed '$d'; }
[ "${1:-help}" = help ] && { usage; exit 0; }
load_context
[ -n "${WEB_OUT:-}" ] || { echo "set WEB_OUT=<evidence dir> on this call: WEB_OUT=… $0 $1"; exit 2; }
OUT="$WEB_OUT"
mkdir -p "$OUT"
# Pinned so every machine runs the same browser build (Chromium 1194); `setup` downloads it once.
PW_VERSION=1.56.1
DRV="$HOME/.cache/product-engineer/web"
PW="$DRV/node_modules/.bin/playwright"

need_url() { [ -n "${WEB_URL:-}" ] || { echo "WEB_URL missing in $CONTEXT (§ Test surfaces env block)"; exit 2; }; }

js() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g"; }   # a value inside a '…' JS string

write_config() {
  # write_config <record 0|1> <spec file>. The spec is picked by testDir + testMatch here, not by a CLI
  # path: Playwright reads CLI paths as regexes, so "(", "+" or "[" in a path would match nothing.
  # specs import '@playwright/test' from the driver's install (ESM resolves upward from the spec)
  ln -sfn "$DRV/node_modules" "$OUT/node_modules"
  local state=""; [ -f "$OUT/auth.json" ] && state="storageState: '$(js "$OUT/auth.json")',"
  cat > "$OUT/playwright.config.mjs" <<EOF
export default {
  testDir: '$(js "$(dirname "$2")")',
  testMatch: '$(js "$(basename "$2")")',
  outputDir: '$(js "$OUT/results")',
  timeout: 60000,
  workers: 1,
  reporter: 'line',
  use: {
    baseURL: '$(js "${WEB_URL:-}")',
    $state
    viewport: { width: ${WEB_VIEWPORT_W:-1280}, height: ${WEB_VIEWPORT_H:-800} },
    screenshot: '$([ "$1" = 1 ] && echo on || echo only-on-failure)',
    video: '$([ "$1" = 1 ] && echo on || echo off)',
    // recordings play at human speed; the verify pass stays fast
    launchOptions: { slowMo: $([ "$1" = 1 ] && echo "${WEB_SLOWMO:-600}" || echo 0) },
  },
};
EOF
}

spec() {
  # spec <file> <name> <body>: body lines split by real newlines or the two characters \n; nothing else
  # is interpreted (printf %b would eat \\ and \c inside selectors and strings)
  local body="${3//\\n/$'\n'}"
  # recorded runs hold the final state on screen (WEB_HOLD_MS), or the video ends the instant it appears.
  # A step can pass on a page that is broken underneath: collect what went wrong while it ran.
  cat > "$1" <<EOF
import fs from 'node:fs';
import { test, expect } from '@playwright/test';
test('$(js "$2")', async ({ page, baseURL }) => {
const pageErrors = []; let errorsAllowed = false; const allowPageErrors = () => { errorsAllowed = true; };
page.on('pageerror', e => pageErrors.push('uncaught: ' + e.message));
page.on('console', m => { if (m.type() === 'error') pageErrors.push('console.error: ' + m.text()); });
page.on('response', r => { if (r.status() >= 500) pageErrors.push('HTTP ' + r.status() + ' ' + r.url()); });
try {
$body
await page.waitForTimeout(Number(process.env.WEB_HOLD_MS || 0));
} finally {
if (pageErrors.length && process.env.WEB_ERRORS_FILE) fs.writeFileSync(process.env.WEB_ERRORS_FILE, pageErrors.join('\n') + '\n');
}
if (!errorsAllowed) expect(pageErrors.filter(e => e.startsWith('uncaught')), 'uncaught page errors').toEqual([]);
});
EOF
}

run_spec() {
  # run_spec <spec file> <name> <record>: prints the outcome; screenshot on failure or when recording
  local name="${2:-step}"
  write_config "$3" "$1"
  # this run's output only: an older errors log or failure shot of the same step would mislead
  rm -rf "$OUT/results" "$OUT/page-errors.log" "$OUT/${name}-errors.log"
  WEB_ERRORS_FILE="$OUT/page-errors.log" WEB_HOLD_MS=$([ "$3" = 1 ] && echo 1500 || echo 0) \
    "$PW" test -c "$OUT/playwright.config.mjs" > "$OUT/run.log" 2>&1
  local rc=$?
  grep -E "passed|failed|Error:|expect\(|No tests found" "$OUT/run.log" | head -6
  if [ -s "$OUT/page-errors.log" ]; then
    mv "$OUT/page-errors.log" "$OUT/${name}-errors.log"
    echo "page errors ($OUT/${name}-errors.log):"; head -5 "$OUT/${name}-errors.log"
  fi
  echo "PLAYWRIGHT EXIT $rc"
  local shot; shot=$(find "$OUT/results" -name '*.png' 2>/dev/null | sort | tail -1)
  if [ "$3" = 1 ]; then
    [ -n "$shot" ] && cp "$shot" "$OUT/$name.png" && echo "shot: $OUT/$name.png"
    local webm; webm=$(find "$OUT/results" -name '*.webm' 2>/dev/null | head -1)
    if [ -n "$webm" ]; then
      mkdir -p "$OUT/clips"
      local n; n=$(printf "%03d" $(( $(ls "$OUT/clips" | wc -l) + 1 )))
      "$MEDIA" mp4 "$webm" "$OUT/clips/$n-$name.mp4" >/dev/null || { echo "video: mp4 conversion failed"; rc=1; }
    fi
  elif [ $rc -ne 0 ] && [ -n "$shot" ]; then
    cp "$shot" "$OUT/fail-$name.png" && echo "shot: $OUT/fail-$name.png"
  fi
  [ $rc -eq 0 ] && rm -f "$OUT/fail-$name.png"
  return $rc
}

case "${1:-status}" in
  status)
    echo "web: ${WEB_URL:-<WEB_URL unset>}   evidence: $OUT"
    [ -x "$PW" ] && echo "driver: playwright $PW_VERSION" || echo "driver: missing -> web.sh setup"
    if [ -n "${WEB_URL:-}" ]; then
      code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${WEB_READY_URL:-$WEB_URL}")
      [ "$code" = 000 ] && echo "app: not reachable (web.sh start?)" || echo "app: HTTP $code"
    fi
    [ -f "$OUT/auth.json" ] && echo "login: saved session ($OUT/auth.json)" || echo "login: none (web.sh login when the app needs it)"
    ;;
  setup)
    mkdir -p "$DRV" && cd "$DRV" && { [ -f package.json ] || npm init -y >/dev/null; }
    npm i -s "@playwright/test@$PW_VERSION" ffmpeg-static@5.3.0 >/dev/null 2>&1 || { echo "npm install failed"; exit 1; }
    "$PW" install chromium >/dev/null 2>&1 || { echo "browser install failed (network? run: $PW install chromium)"; exit 1; }
    echo "driver ready: playwright $PW_VERSION"
    ;;
  start)
    # start the app locally with the project's command, then wait until it answers
    need_url; [ -n "${WEB_START_CMD:-}" ] || { echo "WEB_START_CMD unset: the app runs elsewhere ($WEB_URL)"; exit 0; }
    curl -s -o /dev/null --max-time 3 "${WEB_READY_URL:-$WEB_URL}" && { echo "app: already up"; exit 0; }
    cd "$REPO" && nohup bash -c "$WEB_START_CMD" > "$OUT/app.log" 2>&1 &
    for _ in $(seq 1 90); do curl -s -o /dev/null --max-time 3 "${WEB_READY_URL:-$WEB_URL}" && { echo "app: up"; exit 0; }; sleep 2; done
    echo "app: not up after 3 min, see $OUT/app.log"; exit 1
    ;;
  login)
    # The user logs in by hand in a real browser window; the session (cookies, storage) is saved and
    # reused by every step. Passwords never pass through the skill. Close the window when done.
    need_url
    (cd "$DRV" && "$PW" codegen --save-storage="$OUT/auth.json" "$WEB_URL") >/dev/null 2>&1
    [ -f "$OUT/auth.json" ] && echo "session saved: $OUT/auth.json" || echo "no session saved"
    ;;
  step)
    # Steps don't share a page: each starts from page.goto(...) and leaves nothing behind.
    need_url; [ -x "$PW" ] || "$0" setup
    spec "$OUT/step.spec.mjs" "${3:-step}" "$2"
    run_spec "$OUT/step.spec.mjs" "${3:-}" 0; rc=$?
    # -forced steps depend on temporary code that is gone by the replay: never saved
    if [ $rc -eq 0 ] && [[ "${3:-}" == ac* ]] && [[ "${3:-}" != *-forced ]]; then
      mkdir -p "$OUT/flows"; cp "$OUT/step.spec.mjs" "$OUT/flows/$3.spec.mjs"; echo "saved: flows/$3.spec.mjs"
    fi
    exit $rc
    ;;
  replay)
    # evidence run: every saved flow in AC order, recorded (Playwright video -> mp4) + final screenshot
    flows=(); while IFS= read -r f; do flows+=("$f"); done < <(ls "$OUT/flows"/*.spec.mjs 2>/dev/null | sort -V)
    [ ${#flows[@]} -gt 0 ] || { echo "no saved flows in $OUT/flows"; exit 1; }
    rm -rf "$OUT/clips"; failed=""
    for f in "${flows[@]}"; do
      n=$(basename "$f" .spec.mjs); echo "== $n"
      run_spec "$f" "$n" 1 || failed="$failed $n"
    done
    clips=(); while IFS= read -r c; do clips+=("$c"); done < <(ls "$OUT/clips"/*.mp4 2>/dev/null | sort -V)
    if [ ${#clips[@]} -gt 0 ]; then "$MEDIA" join "$OUT/workflow.mp4" "${clips[@]}" || failed="$failed video"; else failed="$failed video"; fi
    for ac in $(ls "$OUT/flows" | grep -o '^ac[0-9]*' | sort -uV); do
      acc=(); for c in ${clips[@]+"${clips[@]}"}; do case "$(basename "$c")" in *-"$ac"-*) acc+=("$c") ;; esac; done
      if [ ${#acc[@]} -gt 0 ]; then "$MEDIA" join "$OUT/$ac.mp4" "${acc[@]}" || failed="$failed video-$ac"; else failed="$failed video-$ac"; fi
    done
    [ -z "$failed" ] && echo "REPLAY: all steps passed" || { echo "REPLAY FAILED:$failed"; exit 1; }
    ;;
  shot)
    # shot <name> [path]: screenshot of a page (default WEB_URL) with the saved session
    need_url; [ -x "$PW" ] || "$0" setup
    spec "$OUT/shot.spec.mjs" "shot" "allowPageErrors();\nawait page.goto('$(js "${3:-/}")');\nawait page.waitForLoadState('networkidle');\nawait page.screenshot({ path: '$(js "$OUT/${2:-shot}.png")', fullPage: true });"
    run_spec "$OUT/shot.spec.mjs" "shot-${2:-shot}" 0 >/dev/null && echo "shot: $OUT/${2:-shot}.png" \
      || { echo "shot failed, see $OUT/run.log"; exit 1; }
    ;;
  inspect)
    # inspect [path]: the accessibility tree of a page (default WEB_URL) with the saved session — the
    # roles and names getByRole needs, so selectors come from the page instead of guesses
    need_url; [ -x "$PW" ] || "$0" setup; rm -f "$OUT/inspect.txt"
    spec "$OUT/inspect.spec.mjs" "inspect" "allowPageErrors();\nawait page.goto('$(js "${2:-/}")');\nawait page.waitForLoadState('networkidle');\nfs.writeFileSync('$(js "$OUT/inspect.txt")', await page.locator('body').ariaSnapshot());"
    run_spec "$OUT/inspect.spec.mjs" "inspect" 0 | grep -v 'PLAYWRIGHT EXIT 0'
    [ -s "$OUT/inspect.txt" ] && { head -200 "$OUT/inspect.txt"; echo; } || { echo "inspect failed, see $OUT/run.log"; exit 1; }
    ;;
  video)
    clips=(); while IFS= read -r c; do clips+=("$c"); done < <(ls "$OUT/clips"/*.mp4 2>/dev/null | sort -V | grep -- "${3:-}")
    [ ${#clips[@]} -gt 0 ] || { echo "no clips in $OUT/clips"; exit 1; }
    "$MEDIA" join "$OUT/${2:-workflow}.mp4" "${clips[@]}"
    ;;
  *) usage; exit 2 ;;
esac
