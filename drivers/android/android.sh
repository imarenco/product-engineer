#!/usr/bin/env bash
# Native Android test surface (Kotlin / Java, or any app without a JS bundler): drive the Android
# emulator through Maestro for AC verification. Every code change needs `build` (ANDROID_BUILD_CMD:
# e.g. ./gradlew installDebug) before the app shows it; `needs` says when.
# Usage: android.sh <help|prefs|logs|…the commands below> [...]
#   prefs [file-substring]   the app's SharedPreferences XML (debug builds: run-as) — probe state the UI doesn't show
#   logs <text> [lines]      logcat lines of the app's own process
#   SIM_OUT — required on every call (SIM_PLATFORM is not needed: always android).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DRV_PLATFORM=android
# dependency manifests: `setup` (SETUP_CMD, when the project has one) only when one changed
DEPS=(build.gradle build.gradle.kts settings.gradle settings.gradle.kts gradle/libs.versions.toml)
FORCE_NEEDS_BUILD=1
. "$HERE/../maestro/core.sh"

case "${1:-status}" in
  prefs)
    s=$(serial); [ -n "$s" ] || { echo "no emulator running: android.sh boot"; exit 1; }
    files=$(adb -s "$s" shell run-as "$APP" ls shared_prefs 2>/dev/null | tr -d '\r') \
      || { echo "prefs: run-as failed (release build, or $APP not installed)"; exit 1; }
    for f in $files; do
      case "$f" in *"${2:-}"*) echo "== $f"; adb -s "$s" exec-out run-as "$APP" cat "shared_prefs/$f" ;; esac
    done
    ;;
  logs)
    s=$(serial); [ -n "$s" ] || { echo "no emulator running: android.sh boot"; exit 1; }
    pid=$(adb -s "$s" shell pidof "$APP" | tr -d '\r')
    [ -n "$pid" ] || { echo "logs: $APP is not running (relaunch first)"; exit 1; }
    adb -s "$s" logcat -d --pid="$pid" | grep -- "${2:?usage: android.sh logs <text> [lines]}" | tail -"${3:-40}"
    ;;
  *) core "$@" ;;
esac
