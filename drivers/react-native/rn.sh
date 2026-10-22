#!/usr/bin/env bash
# React Native test surface: drive the iOS simulator or Android emulator through Maestro for AC
# verification. One Maestro flow per call: a tap queued behind a closing modal or an open keyboard is
# lost or lands on the next screen. JS changes load from Metro: no rebuild unless native code changed.
# Usage: rn.sh <help|metro|reload|quiet|mmkv|logs|…the commands below> [...]
#   metro [reset]          start the bundler (resets its cache by itself after a branch or dependency change)
#   reload                 reload the JS through Metro
#   quiet <on|off>         LogBox toasts off/on (a `TEMPTEST quiet` line in index.js; relaunch to apply)
#   mmkv <key> [n]         last n writes to matching MMKV keys (IOS_STATE_FILE / ANDROID_STATE_FILE)
#   force …                edits `const|let NAME = …; // TEMPTEST` lines; Metro serves the edit, no rebuild
#   logs <text> [lines]    Android only: JS console output from logcat (tag ReactNativeJS)
#   SIM_PLATFORM  ios | android — required on every call, with SIM_OUT. METRO_PORT, IOS_STATE_FILE and
#   ANDROID_STATE_FILE come from the project context.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# What the slow steps depend on. shortcut: any manifest/lockfile change counts as native — a JS-only
# dependency bump costs a rebuild it didn't need; fine at a few rebuilds a week.
DEPS=(package.json package-lock.json yarn.lock patches)
NATIVE=(ios android "${DEPS[@]}")
NATIVE_NOTE="JS comes from Metro"
RELAUNCH_SETTLE=15
. "$HERE/../maestro/core.sh"

metro_up() { [ -n "${METRO_PORT:-}" ] && curl -s --max-time 2 "http://localhost:$METRO_PORT/status" | grep running >/dev/null; }
# the emulator reaches the bundler on the host through the reversed port
pre_launch() { [ -n "${METRO_PORT:-}" ] && [ -n "${1:-}" ] && adb -s "$1" reverse "tcp:$METRO_PORT" "tcp:$METRO_PORT" >/dev/null; return 0; }
status_extra() { metro_up && echo "metro: running" || echo "metro: down"; }
# this repo's Metro watches node_modules while npm ci replaces it (other projects' bundlers run on
# other ports and stay up)
pre_setup() { pkill -f "react-native start --port ${METRO_PORT:-8081}" 2>/dev/null; return 0; }

case "${1:-status}" in
  setup)
    # npm ci fails with ENOTEMPTY while a Gradle daemon (e.g. the IDE's) holds files in node_modules.
    # Stop the daemons only then — through the project's own wrapper — and retry once.
    (core setup) && exit 0
    grep -q ENOTEMPTY "$OUT/setup.log" 2>/dev/null && [ -x "$REPO/android/gradlew" ] || exit 1
    echo "setup: ENOTEMPTY — stopping Gradle daemons (./gradlew --stop) and retrying"
    (cd "$REPO/android" && ./gradlew --stop >/dev/null 2>&1)
    core setup
    ;;
  needs)
    (core needs)
    d=$(fp "${DEPS[@]}")
    if metro_up && [ "$(stamped metro)" != "$(git -C "$REPO" branch --show-current) $d" ]; then
      echo "metro: running, but branch or dependencies changed since it started -> stop it, then \`metro\`"
    fi
    ;;
  metro)
    [ -n "${METRO_PORT:-}" ] || { echo "no bundler (METRO_PORT unset in project context)"; exit 0; }
    metro_up && { echo "metro: already running"; exit 0; }
    # A clean cache costs a minute of bundling: only after a branch or dependency change (or `metro reset`).
    cur="$(git -C "$REPO" branch --show-current) $(fp "${DEPS[@]}")"
    reset=; { [ -n "${2:-}" ] || [ "$(stamped metro)" != "$cur" ]; } && reset=--reset-cache
    echo "metro: starting ${reset:-with the existing cache}"
    cd "$REPO" && nohup npx react-native start --port "$METRO_PORT" $reset > "$OUT/metro.log" 2>&1 &
    # stamped only once it's up: a Metro that failed to start must get its cache reset next time
    for _ in $(seq 1 60); do metro_up && { stamp metro "$cur"; echo "metro: up"; exit 0; }; sleep 2; done
    echo "metro: failed to start, see $OUT/metro.log"; exit 1
    ;;
  reload)
    metro_up && curl -s -X POST "http://localhost:$METRO_PORT/reload" >/dev/null && echo "reloaded" \
      || echo "no bundler running: relaunch instead"
    ;;
  quiet)
    # LogBox toasts cover tab bars and buttons in Debug builds: silence them for the whole run.
    # The line is TEMPTEST, so the leftover check finds it if `quiet off` is forgotten.
    f="$REPO/index.js"; [ -f "$f" ] || { echo "quiet: no index.js (not React Native?)"; exit 1; }
    sed -i '' '/\/\/ TEMPTEST quiet/d' "$f"
    if [ "${2:-on}" = on ]; then
      { echo "require('react-native').LogBox.ignoreAllLogs(true); // TEMPTEST quiet"; cat "$f"; } > "$f.tmp" && mv "$f.tmp" "$f"
      echo "quiet: on (relaunch to apply)"
    else echo "quiet: off"; fi
    ;;
  mmkv)
    # mmkv <key-substring> [n]: last n writes to matching MMKV keys, oldest first; the last is the live
    # value. Use it to probe app state: RN 0.81 JS logs reach neither iOS os_log nor Metro (Android: `logs`).
    if [ "$PLATFORM" = android ]; then
      # debug builds only: run-as reads the app's private files
      adb -s "$(serial)" exec-out run-as "$APP" cat "${ANDROID_STATE_FILE:?ANDROID_STATE_FILE missing in project context}" > "$OUT/mmkv.default" || exit 1
      F="$OUT/mmkv.default"
    else
      D=$(xcrun simctl get_app_container "$UDID" "$APP" data) || exit 1
      F="$D/${IOS_STATE_FILE:?IOS_STATE_FILE missing in project context}"
    fi
    python3 -I "$HERE/mmkv.py" "$F" "$2" | tail -"${3:-3}"
    ;;
  logs)
    # logs <text> [lines]: Android only — JS console/getLogger output reaches logcat (tag ReactNativeJS).
    # iOS has no equivalent on RN 0.81: probe state with `mmkv` instead.
    [ "$PLATFORM" = android ] || { echo "logs: Android only; on iOS use: rn.sh mmkv <key>"; exit 1; }
    adb -s "$(serial)" logcat -d -s ReactNativeJS:V | grep -- "$2" | tail -"${3:-40}"
    ;;
  *) core "$@" ;;
esac
