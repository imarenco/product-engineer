# Commands every mobile driver has (react-native/rn.sh, ios/ios.sh, android/android.sh):
#   status · boot · setup · needs · build · relaunch [settle-s] · inspect · shot <name> · verify · replay
#   a11y <name>: the controls on the current screen a screen reader can't name (-> $SIM_OUT/a11y-<name>.txt)
#   verify: every saved flow once, unrecorded — the fix loop's regression check in one call
#   step '<maestro commands, \n separated>' [ac<N>-<k>-<state> | look-<x>] [settle-s]
#   force <file> NAME=<value>… [shot <name>]   set `const|let|var|val NAME = …  // TEMPTEST` lines, relaunch, screenshot
#   video <name> [clip-filter] · frame | jpg | publish (scripts/media.sh)
#   SIM_OUT evidence dir — required on every call (`help` excepted). Project values (APP_ID, IOS_DEVICE,
#   IOS_RUNTIME, IOS_UDID, ANDROID_AVD, SETUP_CMD, IOS_BUILD_CMD, ANDROID_BUILD_CMD, ANDROID_APK) come from
#   the ```env block of the project context (.claude/project-context.md, else the § Project context of
#   AGENTS.md / CLAUDE.md; PROJECT_CONTEXT overrides). FORCE_SETTLE: the seconds `force` waits;
#   MAESTRO_CALL_TIMEOUT: the seconds one Maestro call may take (default 600).
# Which device (`status` says which and why):
#   iOS: SIM_UDID (this call) > IOS_UDID (context, one machine) > IOS_DEVICE + IOS_RUNTIME (context, by
#     name: the same on every machine; newest iOS when no runtime) > fallback: a booted simulator, one
#     with the app installed first (`boot`: else the newest iPhone). Kept per repo, so every call of a
#     run uses the same one until the configuration changes.
#   Android: SIM_SERIAL (this call; a physical device: screenshots, no video) > the emulator running
#     SIM_AVD / ANDROID_AVD > fallback: the first running emulator (`boot`: else the first AVD).
# Sourced by a driver, which first sets DRV_PLATFORM (or leaves it to SIM_PLATFORM), DEPS / NATIVE
# (path arrays for `needs`), NATIVE_NOTE, RELAUNCH_SETTLE and FORCE_NEEDS_BUILD, and may define the
# hooks pre_launch (Android, before build/relaunch), pre_setup and status_extra. It then runs
# `core "$@"` for any command it doesn't handle itself.
CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEDIA="$CORE/../../scripts/media.sh"
# shellcheck source=../../scripts/context.sh
. "$CORE/../../scripts/context.sh"
DRV_NAME="$(basename "$0")"
usage() { sed -n '2,/^set -uo/p' "$0" | sed '$d'; echo "#"; sed -n '1,/^# Sourced by/p' "$CORE/core.sh" | sed '$d'; }
[ "${1:-help}" = help ] && { usage; exit 0; }
load_context
# Shell state doesn't survive between agent tool calls: platform and evidence dir are passed on every
# call, never defaulted, so a step can't silently run on the wrong device or save to the wrong place.
PLATFORM="${DRV_PLATFORM:-${SIM_PLATFORM:-}}"
case "$PLATFORM" in ios|android) ;; *) echo "set SIM_PLATFORM=<ios|android> on this call: SIM_PLATFORM=ios SIM_OUT=… $0 $1"; exit 2 ;; esac
[ -n "${SIM_OUT:-}" ] || { echo "set SIM_OUT=<evidence dir> on this call: SIM_OUT=… $0 $1"; exit 2; }
AVD="${SIM_AVD:-${ANDROID_AVD:-}}"
APP="${APP_ID:-}"
if [ -z "$APP" ] && [ "${1:-}" != publish ] && [ "${1:-}" != jpg ] && [ "${1:-}" != frame ]; then
  echo "APP_ID missing: add a \`\`\`env block to the project context (${CONTEXT:-.claude/project-context.md}; see the skill's templates/project-context.md)"; exit 2
fi
OUT="$SIM_OUT"
mkdir -p "$OUT" && OUT="$(cd "$OUT" && pwd)"   # absolute: drivers cd into the repo
export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
# appended, never prepended: the user's own node/ruby/java (nvm, asdf, rbenv…) must win; these only
# fill in what a non-interactive shell's PATH lacks
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.rbenv/shims:$HOME/.maestro/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"
# Android builds and Maestro need JDK 17: a registered one (-F: no silent fallback to another
# version), else Homebrew's, else whatever JAVA_HOME the caller has
# Homebrew's, Apple Silicon (/opt/homebrew) or Intel (/usr/local)
JDK17="$(/usr/libexec/java_home -F -v 17 2>/dev/null)" || for j in /opt/homebrew /usr/local; do
  [ -d "$j/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" ] && { JDK17="$j/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"; break; }
done
export JAVA_HOME="${JDK17:-${JAVA_HOME:-}}"
export MAESTRO_DRIVER_STARTUP_TIMEOUT=120000
[ -n "${DEPS+x}" ] || DEPS=()
[ -n "${NATIVE+x}" ] || NATIVE=(. ':(exclude)*.md')

hook() { declare -F "$1" >/dev/null && "$@"; return 0; }
# Recording is on while $OUT/.recording exists: the forced-video recipe touches it (empty) across
# calls; replay writes `replay <pid>`, and a replay that was killed hard leaves it behind — dead
# owner = stale, removed, so later steps still save their flows.
recording() {
  [ -f "$OUT/.recording" ] || return 1
  local who="" pid=""; read -r who pid < "$OUT/.recording" 2>/dev/null
  # no pid → stale too (`kill -0` with no pid would signal our own process group and "succeed")
  if [ "$who" = replay ] && { [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; }; then rm -f "$OUT/.recording"; return 1; fi
  return 0
}
# The Android device: SIM_SERIAL when given; else the running emulator whose AVD is the configured
# one; else (no AVD configured) the first emulator. Empty = none running.
serial() {
  [ -n "${SIM_SERIAL:-}" ] && { echo "$SIM_SERIAL"; return; }
  local s
  for s in $(adb devices 2>/dev/null | awk '/^emulator-[0-9]+\tdevice/{print $1}'); do
    if [ -z "$AVD" ] || [ "$(adb -s "$s" emu avd name 2>/dev/null | head -1 | tr -d '\r')" = "$AVD" ]; then
      echo "$s"; return
    fi
  done
}
device_id() { if [ "$PLATFORM" = android ]; then serial; else echo "$UDID"; fi; }

# What the slow steps depend on, so `needs` can skip them. -w: pod install re-indents project.pbxproj
# lines, and whitespace-only churn must not force a rebuild. Untracked files count too (a new source
# file needs a build); .claude/ never does.
STAMPS="$REPO/.claude/work/.sim"
fp() {
  [ $# -gt 0 ] || { echo none; return; }
  # outside a git repo there is nothing to fingerprint: never a value that could match a stamp
  (cd "$REPO" && git rev-parse --git-dir >/dev/null 2>&1) || { echo "unknown-$RANDOM$RANDOM"; return; }
  # quotePath=false: git otherwise prints non-ASCII names quoted, and those files would be skipped
  (cd "$REPO" && { git -c core.quotePath=false ls-files -s -- "$@" ':(exclude).claude'
    git -c core.quotePath=false diff -w HEAD -- "$@" ':(exclude).claude'
    git -c core.quotePath=false ls-files -o --exclude-standard -- "$@" ':(exclude).claude' |
      while IFS= read -r f; do echo "$f $(git hash-object -- "$f")"; done; } 2>/dev/null | shasum | cut -c1-12)
}
# Changes whenever the app is (re)installed, by this driver or by anyone else.
installed_id() {
  if [ "$PLATFORM" = android ]; then
    s=$(serial); [ -n "$s" ] && adb -s "$s" shell dumpsys package "$APP" 2>/dev/null | grep -m1 lastUpdateTime | tr -d ' \r'
  else
    c=$(xcrun simctl get_app_container "$UDID" "$APP" app 2>/dev/null) && stat -f %m "$c/Info.plist"
  fi
}
stamp() { mkdir -p "$STAMPS" && echo "$2" > "$STAMPS/$1"; }
stamped() { cat "$STAMPS/$1" 2>/dev/null; }

# The iOS simulator, by the order in the header. The pick is stamped with the configuration it was
# made for: a run's calls (the forced dir included) keep the same simulator even when another one is
# booted meanwhile; a changed IOS_DEVICE / IOS_RUNTIME, or a deleted simulator, picks again.
UDID=""; UDID_FROM=""
resolve_ios() {
  if [ -n "${SIM_UDID:-}" ]; then UDID=$SIM_UDID; UDID_FROM=SIM_UDID; return 0; fi
  if [ -n "${IOS_UDID:-}" ]; then UDID=$IOS_UDID; UDID_FROM=IOS_UDID; return 0; fi
  local key="${IOS_DEVICE:-}|${IOS_RUNTIME:-}" line got
  line=$(stamped ios-device)
  if [ "${line%%$'\t'*}" = "$key" ]; then
    got=${line#*$'\t'}
    # no `grep -q` after a pipe: under pipefail its early exit SIGPIPEs xcrun → a false "gone"
    if xcrun simctl list devices | grep -F "(${got%%$'\t'*})" >/dev/null; then
      UDID=${got%%$'\t'*}; UDID_FROM="$(printf '%s' "$got" | cut -f2- | tr '\t' ' ') (kept)"; return 0
    fi
  fi
  got=$(python3 -I "$CORE/pick_sim.py" "${IOS_DEVICE:-}" "${IOS_RUNTIME:-}" "$APP" ${1:+"$1"}) || return 1
  UDID=${got%%$'\t'*}; UDID_FROM=$(printf '%s' "$got" | cut -f2- | tr '\t' ' ')
  stamp ios-device "$key"$'\t'"$got"
}
if [ "$PLATFORM" = ios ]; then
  case "${1:-}" in
    frame|jpg|publish|setup) ;;
    boot) resolve_ios boot || exit 1 ;;
    status) resolve_ios ;;
    *) resolve_ios || exit 1 ;;
  esac
fi

screenshot() {
  if [ "$PLATFORM" = android ]; then
    adb -s "$(serial)" exec-out screencap -p > "$1" 2>/dev/null && [ -s "$1" ]
  else
    xcrun simctl io "$UDID" screenshot "$1" >/dev/null 2>&1
  fi
}

next_clip() {
  mkdir -p "$OUT/clips"
  printf "%s/clips/%03d-%s.mp4" "$OUT" $(( $(ls "$OUT/clips" | wc -l) + 1 )) "$1"
}
# iOS: simctl recordVideo. Android: the emulator console records on the host (`adb emu screenrecord`);
# never the device's `adb screenrecord` (Maestro's screenshots stall ~95 s per command next to it) nor
# Maestro's startRecording (one frame per clip, 2026-10-17).
clip_start() {
  CLIP=$(next_clip "$1")   # run_flow drops it when the step fails
  if [ "$PLATFORM" = android ]; then
    echo "$CLIP" > "$OUT/rec.target"; rm -f "$OUT/rec.webm"
    adb -s "$(serial)" emu screenrecord start --fps 15 --size 540x1212 "$OUT/rec.webm" > "$OUT/rec.log" 2>&1
  else
    nohup xcrun simctl io "$UDID" recordVideo --codec h264 --force "$CLIP" > "$OUT/rec.log" 2>&1 &
    echo $! > "$OUT/rec.pid"; sleep 1
  fi
}
clip_stop() {
  if [ -f "$OUT/rec.target" ]; then
    local target i=0; target=$(cat "$OUT/rec.target"); rm -f "$OUT/rec.target"
    adb -s "$(serial)" emu screenrecord stop >> "$OUT/rec.log" 2>&1
    # the console returns before the WebM is finalized: wait until its size stops changing (bounded)
    local last=-1 size=0
    while [ $i -lt 50 ]; do
      size=$(stat -f %z "$OUT/rec.webm" 2>/dev/null || echo 0)
      [ "$size" -gt 0 ] && [ "$size" = "$last" ] && break
      last=$size; sleep 0.3; i=$((i+1))
    done
    "$MEDIA" mp4 "$OUT/rec.webm" "$target" >/dev/null && rm -f "$OUT/rec.webm" \
      || { rm -f "$target" "$OUT/rec.webm"; echo "video: emulator clip conversion failed"; }
    return 0
  fi
  [ -f "$OUT/rec.pid" ] || return 0
  local pid i=0; pid=$(cat "$OUT/rec.pid")
  # a pid left by a killed run may belong to another process by now: only signal a recorder
  ps -p "$pid" -o command= 2>/dev/null | grep recordVideo >/dev/null || { rm -f "$OUT/rec.pid"; return 0; }
  kill -INT "$pid" 2>/dev/null
  # the MP4 is only valid once recordVideo has finished writing (bounded: a stale pid can't hang us)
  while kill -0 "$pid" 2>/dev/null && [ $i -lt 75 ]; do sleep 0.2; i=$((i+1)); done
  kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
  rm -f "$OUT/rec.pid"
}

session() { SIM_SESSION="$REPO" python3 "$CORE/../../scripts/maestro_session.py" "$@"; }
run_flow() {
  # run_flow <flow.yaml> <name> <settle>: recording on -> clip + screenshot; failure -> fail-<name>.png
  local flow="$1" rc name="${2:-step}"
  [ "$PLATFORM" = ios ] && xcrun simctl terminate "$UDID" com.apple.DocumentsApp 2>/dev/null
  # One Maestro session for the whole run (scripts/maestro_session.py): the driver starts once
  # (~20 s), then each flow costs ~1 s instead of a ~30 s `maestro test`. Connect before recording
  # so the startup stays out of the video.
  recording && { session warm "$(device_id)" >/dev/null; clip_start "$name"; }
  session run "$(device_id)" "$flow" > "$OUT/maestro.log" 2>&1; rc=$?
  cat "$OUT/maestro.log"; echo "MAESTRO EXIT $rc"
  if [ $rc -ne 0 ]; then
    # a failing step is never evidence of the state it was meant to reach — not even while recording
    # (a replay or a forced-state recording): its shot is a fail- shot, and its clip is dropped below
    screenshot "$OUT/fail-$name.png" && echo "shot: $OUT/fail-$name.png"
  elif recording; then
    sleep "$3"; screenshot "$OUT/$name.png" && echo "shot: $OUT/$name.png"
  fi
  # an old failure shot of a step that passes now must not be published as a failure
  [ $rc -eq 0 ] && rm -f "$OUT/fail-$name.png"
  clip_stop
  [ $rc -ne 0 ] && [ -n "${CLIP:-}" ] && rm -f "$CLIP"
  # a recorder that died leaves a passing step with no clip: say so now, not when `video` finds a gap
  [ $rc -eq 0 ] && [ -n "${CLIP:-}" ] && [ ! -s "$CLIP" ] && echo "video: no clip recorded for $name"
  CLIP=""
  return $rc
}

core() {
case "${1:-status}" in
  status)
    echo "driver: $DRV_NAME   platform: $PLATFORM   evidence: $OUT"
    if [ "$PLATFORM" = android ]; then
      s=$(serial)
      if [ -n "${SIM_SERIAL:-}" ]; then from=SIM_SERIAL; elif [ -n "$AVD" ]; then from="AVD $AVD"; else from="fallback: first running emulator"; fi
      echo "emulator: ${s:-none running ($DRV_NAME boot)} — $from"
      # no `grep -q` after a pipe: under pipefail its early exit SIGPIPEs the producer → false "NOT installed"
      [ -n "$s" ] && { adb -s "$s" shell pm path "$APP" >/dev/null 2>&1 \
        && echo "app: installed on $s" || echo "app: NOT installed on $s"; }
    else
      if [ -n "$UDID" ]; then echo "simulator: $UDID — $UDID_FROM"
      elif [ -n "${IOS_DEVICE:-}" ]; then echo "simulator: none — IOS_DEVICE \"$IOS_DEVICE\"${IOS_RUNTIME:+ on iOS $IOS_RUNTIME} matches no simulator here (see above)"
      else echo "simulator: none — set IOS_DEVICE in the project context, or boot one"; fi
      echo "booted:"; xcrun simctl list devices booted | grep -E '\(' || echo "  none"
      [ -n "$UDID" ] && { xcrun simctl get_app_container "$UDID" "$APP" >/dev/null 2>&1 \
        && echo "app: installed on $UDID" || echo "app: NOT installed on $UDID"; }
    fi
    hook status_extra
    command -v maestro >/dev/null && echo "maestro: $(maestro --version 2>/dev/null)" \
      || echo 'maestro: missing -> curl -Ls "https://get.maestro.mobile.dev" | bash'
    ;;
  needs)
    # Which slow steps this checkout needs; skip the ones marked "not needed".
    if [ -n "${SETUP_CMD:-}" ]; then
      [ "$(stamped setup)" = "$(fp ${DEPS[@]+"${DEPS[@]}"})" ] && echo "setup: not needed (dependencies unchanged since the last setup)" \
        || echo "setup: NEEDED (dependencies differ from the last setup, or none recorded)"
    fi
    id=$(installed_id)
    if [ -z "$id" ]; then echo "build: NEEDED (app not installed)"
    elif [ "$(stamped "build-$PLATFORM-$(device_id)")" = "$(fp "${NATIVE[@]}") $id" ]; then
      echo "build: not needed (code unchanged since this driver's last build${NATIVE_NOTE:+; $NATIVE_NOTE})"
    else echo "build: NEEDED (code changed, or the app was installed outside this driver)"; fi
    ;;
  boot)
    if [ "$PLATFORM" = android ]; then
      [ -n "$(serial)" ] && { echo "emulator: already running $(serial)"; exit 0; }
      avd="$AVD"; from="ANDROID_AVD"
      [ -n "$avd" ] || { avd=$(emulator -list-avds 2>/dev/null | head -1); from="fallback: first AVD — set ANDROID_AVD to choose"; }
      [ -n "$avd" ] || { echo "no AVD on this machine: create one (Android Studio → Device Manager), then set ANDROID_AVD"; exit 2; }
      echo "emulator: starting $avd ($from)"
      nohup emulator -avd "$avd" -no-snapshot-save -no-boot-anim > "$OUT/emulator.log" 2>&1 &
      epid=$!
      # bounded, and it notices an emulator that died at start (no `adb wait-for-device`: it never returns then)
      for _ in $(seq 1 150); do
        kill -0 "$epid" 2>/dev/null || { echo "emulator: exited during boot, see $OUT/emulator.log"; exit 1; }
        s=$(serial)
        [ -n "$s" ] && [ "$(adb -s "$s" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] \
          && { echo "emulator: booted $s"; exit 0; }
        sleep 2
      done
      echo "emulator: boot timed out, see $OUT/emulator.log"; exit 1
    else
      # bootstatus -b boots if needed and waits until the device is usable; it fails on a bad UDID
      xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 && echo "simulator: booted $UDID — $UDID_FROM" \
        || { echo "simulator: could not boot '$UDID' ($UDID_FROM)"; exit 1; }
    fi
    ;;
  setup)
    [ -n "${SETUP_CMD:-}" ] || { echo "SETUP_CMD missing in project context"; exit 2; }
    hook pre_setup
    # in a subshell: an `exit` inside the project's command must not end this driver silently
    cd "$REPO" && ( eval "$SETUP_CMD" ) > "$OUT/setup.log" 2>&1
    rc=$?; tail -5 "$OUT/setup.log"; echo "SETUP EXIT $rc"
    [ $rc = 0 ] && stamp setup "$(fp ${DEPS[@]+"${DEPS[@]}"})"; exit $rc
    ;;
  build)
    cd "$REPO" || exit 1
    # fingerprint the code the build starts from: edits made while it runs aren't in the app
    built=$(fp "${NATIVE[@]}")
    if [ "$PLATFORM" = android ]; then
      SERIAL=$(serial); [ -n "$SERIAL" ] || { echo "no emulator running: $DRV_NAME boot first"; exit 1; }
      hook pre_launch "$SERIAL"
      : "${ANDROID_BUILD_CMD:?ANDROID_BUILD_CMD missing in project context}"
      ( eval "$ANDROID_BUILD_CMD" ) > "$OUT/build.log" 2>&1
    else
      xcrun simctl boot "$UDID" 2>/dev/null
      : "${IOS_BUILD_CMD:?IOS_BUILD_CMD missing in project context}"
      ( eval "$IOS_BUILD_CMD" ) > "$OUT/build.log" 2>&1
    fi
    rc=$?
    if [ $rc -ne 0 ]; then
      # the error lines, not just the tail: a compiler error is often far above the last lines
      # Kotlin errors start with `e: `; Gradle puts the cause on the line after "What went wrong"
      grep -m20 -A1 -E '^e: |error:|BUILD FAILED|What went wrong|\*\* .* FAILED' "$OUT/build.log" | grep -v '^--$'
      echo "--- last lines:"; tail -5 "$OUT/build.log"
    fi
    echo "BUILD EXIT $rc (log: $OUT/build.log)"
    [ $rc = 0 ] && stamp "build-$PLATFORM-$(device_id)" "$built $(installed_id)"
    grep -q INSTALL_FAILED_UPDATE_INCOMPATIBLE "$OUT/build.log" && echo "The installed app has another \
signature. Once, with the user's OK (it clears the app's data and login): adb uninstall $APP, \
then adb install -r ${ANDROID_APK:-<apk path>}"
    exit $rc
    ;;
  relaunch)
    # launchApp in Maestro resumes the old process and can show stale code
    if [ "$PLATFORM" = android ]; then
      s=$(serial); [ -n "$s" ] || { echo "no emulator running: $DRV_NAME boot first"; exit 1; }
      hook pre_launch "$s"
      adb -s "$s" shell am force-stop "$APP"
      adb -s "$s" shell monkey -p "$APP" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    else
      xcrun simctl terminate "$UDID" com.apple.DocumentsApp 2>/dev/null
      xcrun simctl terminate "$UDID" "$APP" 2>/dev/null
      xcrun simctl launch "$UDID" "$APP" >/dev/null
    fi
    # the exit code is the launch's, so `relaunch && replay` stops when the app didn't start
    rc=$?; [ $rc -eq 0 ] && echo "launched" || { echo "launch failed ($APP)"; exit $rc; }
    sleep "${2:-${RELAUNCH_SETTLE:-5}}"
    ;;
  inspect)
    # Read the screen once, then tap by id/text from it — no guessing and retrying.
    # one line per element a selector can use; the full JSON stays in $OUT/inspect.json
    session inspect "$(device_id)" > "$OUT/inspect.json"; rc=$?
    [ $rc -eq 0 ] || { cat "$OUT/inspect.json"; exit $rc; }
    python3 -I "$CORE/compact_inspect.py" "$OUT/inspect.json" || cat "$OUT/inspect.json"
    ;;
  a11y)
    [ -n "${2:-}" ] || { echo "usage: $DRV_NAME a11y <name>"; exit 2; }; n="$2"
    [[ "$n" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "a11y: the name takes letters, digits, . _ - only"; exit 2; }
    rm -f "$OUT/a11y-$n.txt"
    session inspect "$(device_id)" > "$OUT/inspect.json" || { cat "$OUT/inspect.json"; exit 1; }
    python3 -I "$CORE/compact_inspect.py" "$OUT/inspect.json" --a11y > "$OUT/a11y-$n.txt" \
      || { cat "$OUT/a11y-$n.txt"; rm -f "$OUT/a11y-$n.txt"; echo "a11y: can't read the hierarchy, see $OUT/inspect.json"; exit 1; }
    cat "$OUT/a11y-$n.txt"; echo "a11y: $OUT/a11y-$n.txt"
    ;;
  force)
    # force <file> NAME=<value>… [shot <name>]: one call per forced state. Sets each
    # `const|let|var|val NAME = …  // TEMPTEST …` line in <file> (add those lines first; a type
    # annotation and a trailing `;` are fine), then relaunches — after a rebuild when the driver's
    # code isn't reloaded live — and screenshots.
    f="${2:?usage: force <file> NAME=<value>… [shot <name>]}"; shift 2; shotname=""
    [ -f "$f" ] || { echo "force: no file $f"; exit 1; }
    while [ $# -gt 0 ]; do
      if [ "$1" = shot ]; then shotname="${2:?usage: force <file> NAME=<value>… shot <name>}"; shift 2; continue; fi
      FORCE_KV="$1" python3 - "$f" <<'PY' || exit 1
import os, re, sys
name, value = os.environ["FORCE_KV"].split("=", 1)
p = sys.argv[1]; s = open(p, newline="").read()  # newline="": a CRLF file stays CRLF
pat = re.compile(r"^(\s*(?:(?:export|public|private|internal|static|final|override)\s+)*(?:const|let|var|val) %s(?:\s*:\s*.+?)?\s*=(?![>=])\s*).*?(;?\s*//\s*TEMPTEST.*)$" % re.escape(name), re.M)
s2, n = pat.subn(lambda m: m.group(1) + value + m.group(2), s)
if n != 1:
    sys.exit("force: expected one `const|let|var|val %s = …  // TEMPTEST` line in %s, found %d" % (name, p, n))
open(p, "w", newline="").write(s2); print("force: %s = %s" % (name, value))
PY
      shift
    done
    if [ "${FORCE_NEEDS_BUILD:-0}" = 1 ]; then "$0" build || exit 1; fi
    "$0" relaunch "${FORCE_SETTLE:-${RELAUNCH_SETTLE:-5}}" || exit 1
    if [ -n "$shotname" ]; then
      screenshot "$OUT/$shotname.png" || { echo "shot failed: $shotname"; exit 1; }
      echo "shot: $OUT/$shotname.png"
    fi
    ;;
  step)
    # step '<maestro commands>' [name] [settle-seconds] — commands separated by real newlines or by the
    # two characters \n; nothing else in the body is interpreted (no printf %b escapes).
    # Verification pass: no screenshot unless the flow fails (fail-<name>.png) — use `shot` to look.
    # A passing step named ac* is saved to flows/<name>.yaml; `replay` re-runs them as evidence.
    # Starting the XCTest driver backgrounds the app, and taps then hit SpringBoard ("Search"
    # matched the home-screen pill), so every flow re-foregrounds it without a restart.
    body="${2//\\n/$'\n'}"
    printf 'appId: %s\n---\n- launchApp:\n    stopApp: false\n- waitForAnimationToEnd\n%s\n' "$APP" "$body" > "$OUT/flow.yaml"
    run_flow "$OUT/flow.yaml" "${3:-}" "${4:-2}"; rc=$?
    # -forced steps depend on temporary code that is gone by the replay: never saved
    if [ $rc -eq 0 ] && [[ "${3:-}" == ac* ]] && [[ "${3:-}" != *-forced ]] && ! recording; then
      mkdir -p "$OUT/flows"; cp "$OUT/flow.yaml" "$OUT/flows/$3.yaml"; echo "saved: flows/$3.yaml"
    fi
    exit $rc
    ;;
  verify)
    # verify: every saved flow once, in AC order — no recording, no evidence touched, nothing saved.
    # The fix loop's "re-test everything" in one call (relaunch first).
    flows=(); while IFS= read -r f; do flows+=("$f"); done < <(ls "$OUT/flows"/*.yaml 2>/dev/null | sort -V)
    [ ${#flows[@]} -gt 0 ] || { echo "no saved flows in $OUT/flows"; exit 1; }
    failed=""
    for f in "${flows[@]}"; do
      n=$(basename "$f" .yaml); echo "== $n"
      run_flow "$f" "$n" 0 > "$OUT/.verify.log" 2>&1; rc=$?
      # a pass is one line; a failure shows its reason whatever its wording ("Failed to run flow",
      # "session error", an assertion) — the log is overwritten by the next flow
      if [ $rc -eq 0 ]; then grep -E 'COMPLETED' "$OUT/.verify.log"; else grep -v '^$' "$OUT/.verify.log" | head -6; fi
      [ $rc -eq 0 ] || failed="$failed $n"
    done
    [ -z "$failed" ] && echo "VERIFY: all ${#flows[@]} flows passed" || { echo "VERIFY FAILED:$failed"; exit 1; }
    ;;
  replay)
    # replay: the evidence run. Re-runs every saved flow in AC order (sort -V), recorded, one
    # screenshot per step, then builds workflow.mp4 and ac<N>.mp4. No thinking between steps.
    flows=(); while IFS= read -r f; do flows+=("$f"); done < <(ls "$OUT/flows"/*.yaml 2>/dev/null | sort -V)
    [ ${#flows[@]} -gt 0 ] || { echo "no saved flows in $OUT/flows"; exit 1; }
    # an interrupted replay must not leave the driver recording (steps would stop saving flows), and
    # must stop: without the exit, the loop would go on driving the device for every remaining flow
    trap 'rm -f "$OUT/.recording"; clip_stop' EXIT
    trap 'exit 130' INT TERM
    # this run's evidence only: shots and videos of an earlier replay (or of a deleted flow) would be
    # published with it. Forced shots (`*-forced*`) can't be re-made, so they stay.
    for f in "$OUT"/ac*.png "$OUT"/ac*.jpg "$OUT"/ac[0-9]*.mp4 "$OUT/workflow.mp4"; do
      case "$f" in *-forced*) ;; *) rm -f "$f" ;; esac
    done
    rm -rf "$OUT/clips"; echo "replay $$" > "$OUT/.recording"; failed=""
    for f in "${flows[@]}"; do
      n=$(basename "$f" .yaml); echo "== $n"
      run_flow "$f" "$n" 2 || failed="$failed $n"
    done
    rm -f "$OUT/.recording"
    clips=(); while IFS= read -r c; do clips+=("$c"); done < <(ls "$OUT/clips"/*.mp4 2>/dev/null | sort -V)
    [ ${#clips[@]} -gt 0 ] && "$MEDIA" join "$OUT/workflow.mp4" "${clips[@]}" || failed="$failed video"
    for ac in $(ls "$OUT/flows" | grep -o '^ac[0-9]*' | sort -uV); do
      acc=(); for c in ${clips[@]+"${clips[@]}"}; do case "$(basename "$c")" in *-"$ac"-*) acc+=("$c") ;; esac; done
      [ ${#acc[@]} -gt 0 ] && "$MEDIA" join "$OUT/$ac.mp4" "${acc[@]}" || failed="$failed video-$ac"
    done
    [ -z "$failed" ] && echo "REPLAY: all steps passed" || { echo "REPLAY FAILED:$failed"; exit 1; }
    ;;
  shot)
    screenshot "$OUT/${2:-shot}.png" && echo "shot: $OUT/${2:-shot}.png" || { echo "shot failed"; exit 1; }
    ;;
  video)
    # video <name> [clip-filter]: joins the step clips (all, or those whose name contains the filter)
    clips=(); while IFS= read -r c; do clips+=("$c"); done < <(ls "$OUT/clips"/*.mp4 2>/dev/null | sort -V | grep -- "${3:-}")
    [ ${#clips[@]} -gt 0 ] || { echo "no clips in $OUT/clips"; exit 1; }
    "$MEDIA" join "$OUT/${2:-workflow}.mp4" "${clips[@]}"
    ;;
  frame|jpg|publish)
    "$MEDIA" "$@"
    ;;
  *) usage; exit 2 ;;
esac
}
