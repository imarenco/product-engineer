#!/usr/bin/env bash
# Native iOS test surface (Swift / Objective-C, or any app without a JS bundler): drive the iOS
# simulator through Maestro for AC verification. Every code change needs `build` (IOS_BUILD_CMD:
# build + install on the simulator) before the app shows it; `needs` says when.
# Usage: ios.sh <help|defaults|logs|…the commands below> [...]
#   defaults [key]         the app's UserDefaults (all, or one key) — probe state the UI doesn't show
#   logs <text> [min]      the app's own log lines (os_log, Logger, NSLog, print) from the last N minutes (default 5)
#   SIM_OUT — required on every call (SIM_PLATFORM is not needed: always ios).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DRV_PLATFORM=ios
# dependency manifests: `setup` (SETUP_CMD: pod install, bundle install…) only when one changed
DEPS=(Podfile Podfile.lock Gemfile.lock Package.swift Package.resolved)
FORCE_NEEDS_BUILD=1
. "$HERE/../maestro/core.sh"

case "${1:-status}" in
  defaults)
    # the simulator's defaults command reads the app's preferences domain (bundle id) live
    if [ -n "${2:-}" ]; then xcrun simctl spawn "$UDID" defaults read "$APP" "$2"
    else xcrun simctl spawn "$UDID" defaults read "$APP"; fi
    ;;
  logs)
    # filter by the app's executable name, read from the installed bundle
    c=$(xcrun simctl get_app_container "$UDID" "$APP" app 2>/dev/null) || { echo "logs: $APP not installed on $UDID"; exit 1; }
    exe=$(plutil -extract CFBundleExecutable raw "$c/Info.plist") || exit 1
    xcrun simctl spawn "$UDID" log show --last "${3:-5}m" --style compact \
      --predicate "process == \"$exe\"" 2>/dev/null | grep -- "${2:?usage: ios.sh logs <text> [minutes]}" | tail -40
    ;;
  *) core "$@" ;;
esac
