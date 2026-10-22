# Mobile surfaces — Maestro on the iOS simulator and Android emulator

Generic facts about the tools, true for any app. Facts about one app (its devices, screens, tap
points, login, quirks) live in that repo's project context (§ Test surfaces, § App knowledge).

## Which driver
`$CTX` § Test surfaces `MOBILE_DRIVER` picks it; the surfaces stay `ios` and `android`.
| `MOBILE_DRIVER` | `ios` surface | `android` surface | Code changes reach the app by |
|---|---|---|---|
| `react-native` | `drivers/react-native/rn.sh` + `SIM_PLATFORM=ios` | `drivers/react-native/rn.sh` + `SIM_PLATFORM=android` | Metro (`reload` / `relaunch`); `build` only for native changes — see `references/react-native.md` |
| `native` | `drivers/ios/ios.sh` | `drivers/android/android.sh` | `build` after every code change (`needs` says when) |

Pass `SIM_OUT=$W/shots/<ios|android>` (`$W` = the run's work dir, `SKILL.md` § Paths and
surfaces — `<TICKET>-qa` in `--test-only`), and for `rn.sh` also `SIM_PLATFORM=<ios|android>`, in
front of **every** call: the drivers refuse to run without them. `<driver> help` prints the usage.

## Commands at a glance (`$D` = the driver)
All three share one core (`drivers/maestro/core.sh`):
| Need | Command |
|---|---|
| devices, app install, Maestro (+ bundler for rn.sh) | `$D status` |
| boot the simulator / emulator | `$D boot` (Android: needs `ANDROID_AVD`; bounded wait, fails if the emulator dies) |
| install dependencies (project's SETUP_CMD) | `$D setup` |
| which slow steps are needed (setup / build) | `$D needs` — skip what says "not needed" |
| build + install (project's IOS/ANDROID_BUILD_CMD) | `$D build` (run in background; records the code fingerprint for `needs`) |
| restart the app | `$D relaunch [seconds]` — exits non-zero when the app didn't launch, so `relaunch && replay` stops |
| one test step (a whole state change: act + assert) | `$D step '<maestro commands>' [ac<N>-<k>-<state> \| look-<x>] [settle]` — one long-lived Maestro session: ~20 s to connect once, then ~1–4 s per step |
| read the screen (ids, texts, bounds) before tapping | `$D inspect` (~1 s) |
| one forced state: set values, relaunch, screenshot | `$D force <file> NAME=<value>… [shot <name>]` — edits `const\|let\|var\|val NAME = …  // TEMPTEST` lines (JS, Swift, Kotlin); native drivers rebuild first (minutes) |
| evidence run | `$D replay` |
| screenshot (simctl / adb, no Maestro) | `$D shot <name>` |
| media | `$D video <name> [filter]`; frame/jpg/publish are shared: `<skill>/scripts/media.sh` |

Driver-specific:
| Driver | Command | What |
|---|---|---|
| `rn.sh` | `metro`, `reload`, `quiet on\|off`, `mmkv <key>`, `logs <text>` (Android) | `references/react-native.md` |
| `ios.sh` | `defaults [key]` | the app's UserDefaults — state the UI doesn't show |
| `ios.sh` | `logs <text> [minutes]` | the app process's log lines (os_log, Logger, NSLog, print) |
| `android.sh` | `prefs [file]` | the app's SharedPreferences XML (debug builds) |
| `android.sh` | `logs <text> [lines]` | logcat of the app's own process |

## Maestro (2.x, `~/.maestro/bin`, Java 17)
- Never drive the real mouse (cliclick/AppleScript): the user works on the same machine.
- **Speed** (the drivers keep one `maestro mcp` session per repo, `scripts/maestro_session.py`; it
  exits after 45 min idle, and reconnects by itself when another Maestro process took the device):
  - one step = one whole state change (navigate → act → assert), not one command per step; split
    only where the next rule says. 30–60 one-command steps per ticket was the main cost before.
  - `$D inspect` once per new screen, then tap by the id/text it shows; never guess-and-retry.
  - wait on the screen (`extendedWaitUntil`, `waitForAnimationToEnd`), not fixed sleeps; a failing
    `assertVisible` waits ~17 s before failing, so assert what should be there, not what shouldn't
    (`assertNotVisible` is instant). A wait inside a flow:
    `extendedWaitUntil: {visible: "<never>", timeout: N, optional: true}` — a shell sleep between
    steps doesn't count as evidence.
  - relaunch only for a clean start (forced values, app-start behaviour); otherwise continue from
    the current screen — a relaunch costs 5–15 s of cold start.
  - looks need no Maestro: `$D shot` / `$D force … shot <name>`.
  - don't run a plain `maestro test` while the session is up: it takes the device driver away.
- One flow per `$D step` at these boundaries: a tap queued behind a closing modal or an open
  keyboard is lost or lands on the next screen. State carries over between steps (typed text, open
  sheets): `eraseText` before `inputText`, and leave the screen as the next step expects it.
- The tap right after an overlay closes (e.g. reopening a side panel) is often dropped while the
  close animation runs: put a ~1.5 s `extendedWaitUntil … optional` wait before it. A "close the
  overlay" point tap must sit in the same flow after an `assertVisible` of the overlay — run blind
  after a failed step, it lands on the screen below.
- Every step starts with `launchApp: {stopApp: false}` (added by the driver): starting the iOS driver
  backgrounds the app, and a bare `tapOn: "Search"` then "COMPLETED" on the home screen's Search pill.
- **COMPLETED is not proof** — a tap on the wrong screen completes too. Anchor each AC's first step
  with `assertVisible` of the expected screen, and assert outcomes in the flow.
- Coordinates: **iOS = points** (screenshot px ÷ 3 on a 3× device), **Android = device pixels** (the
  screenshot's own pixels). Percentages must be integers (`"13.6%"` throws NumberFormatException).
  The Read tool shows screenshots scaled — convert from the displayed size. `maestro --device <id>
  hierarchy` prints element bounds (Android: px) when unsure.
- Selectors, best first: test id (`tapOn: {id: "…"}`), exact text, text scoped to a container, then
  points. Points break when layout shifts and can't fail on the wrong screen — anchor them with an
  `assertVisible` first. Never tap a control by point after a timed action (a recording, an upload):
  the control under that point changes with state — re-read the hierarchy and tap by id.
- `assertVisible: "<text>"` matches text and accessibility labels only — a test id (`rid` in
  `inspect` output) needs `assertVisible: {id: "…"}`; an `assertNotVisible` on an id written as text
  always passes (it can't fail).
- Icon-only buttons often expose no text → tap by point; tab labels may be truncated → regex
  (`tapOn: "<label prefix>.*"`).
- Every text selector is a regex: escape `?`, `(`, `)`, `+`, `.` in literal texts —
  `assertNotVisible: "Delete this item?"` also matches an element labelled "Delete this item" and
  fails falsely.
- Useful: `tapOn`, `longPressOn`, `inputText`, `eraseText`, `hideKeyboard`, `pressKey: Enter`,
  `waitForAnimationToEnd`, `extendedWaitUntil: {visible: "…", timeout: 60000}`, `assertVisible`,
  `assertNotVisible`, `scroll`. `back` exists on Android only.
- System sheets are visible: OS permission prompts, iOS `SKStoreReviewController`.
- Known limits → verdict HUMAN: pans/swipes driven by a gesture library don't react to synthesized
  swipes; `tapOn` by text can't see a modal inside a modal (tap by point); a tap right after a modal
  closes in the same flow is often lost.
- Killing a running Maestro (pkill) can relaunch the app on a different screen — re-anchor.
- macOS has no `timeout` command; don't wrap Maestro with it.
- Forcing a state that must change over time (e.g. "fine at launch, failing on resume"): use a time
  switch (`now - start < 30 s ? a : b`), not a call counter — startup code often runs a check twice
  (launch + becoming active), so "first call" is not "launch".

## iOS simulator
- The drivers target the simulator by UDID, resolved from `IOS_DEVICE` (+ `IOS_RUNTIME`) — a name can
  match several devices, so the pick is a booted one first, then the newest iOS. Screenshots:
  `xcrun simctl io <udid> screenshot`.
- The XCTest driver often errors on teardown (`iOS driver not ready in time`, NSPOSIXErrorDomain 64)
  after the taps actually ran: trust the screenshot; on a real timeout just repeat the step
  (`MAESTRO_DRIVER_STARTUP_TIMEOUT=120000` is set). Screenshot-only checks don't need Maestro:
  `$D relaunch` then `$D shot` work when Maestro's driver times out.
- iOS 26.x: an XCTAutomationSupport SIGSEGV (XCTAutomationSession block) in the app's crash log ~1 h
  into a Maestro session is the automation framework, not the app — check the faulting thread
  before reporting a crash; the app then cold-starts, so every ac flow must navigate to its screen.
- Taps sent while the app isn't frontmost hit SpringBoard and can open the Files app; the drivers
  terminate `com.apple.DocumentsApp` and re-foreground the app.
- Background → foreground: `simctl launch <udid> com.apple.Preferences`, wait, then
  `simctl launch <udid> <app id>` (brings the running app back without restarting it).
- Recording: `simctl io recordVideo` keeps idle time (12 s idle = 12 s of video), so the replay
  records only from Maestro's "Launch app" line to the end of each flow. Maestro's own
  `startRecording` hung > 5 min on iOS — don't use it there.
- Never `simctl uninstall` / `clearState` without asking: it logs the user out.

## Android emulator
- Prefer a Google Play system image when the ticket touches Play services. `$D boot` (~17 s).
- `INSTALL_FAILED_UPDATE_INCOMPATIBLE`: the installed app has another signature — uninstall once
  (clears its data/login; ask first), then install the new APK.
- Maestro's `launchApp` grants runtime permissions automatically, so OS permission dialogs don't
  appear in flows (app-level dialogs still do).
- Slower than iOS: ~40 s driver start + 1–3 s per command.
- **Recording** (emulator only): the replay records on the host through the emulator console —
  `adb emu screenrecord start --fps 15 --size 540x1212 <file.webm>` … `stop`, converted to MP4 — from
  Maestro's "Launch app" line to the end of each flow. Never the device's `adb screenrecord` (Maestro's
  screenshots stall ~95 s per command next to it and Maestro won't exit). Maestro's own
  `startRecording` produced a one-frame clip with no duration — don't use it. A full-size console
  recording slowed an already loaded emulator badly; keep the reduced fps/size. A physical Android
  device has no console: no video there (screenshots only).
- A "System UI isn't responding" dialog means the emulator is overloaded (load average > ~8): tap
  Wait, let it settle, and re-run — evidence recorded during it shows the dialog.
- App files: `adb exec-out run-as <app> cat …` (debug builds only) — how `prefs` and `mmkv` read state.
- Play Store-only APIs (e.g. In-App Review) show nothing on sideloaded debug builds → HUMAN unless
  testing a Play-installed build (internal test track / internal app sharing).

## Native apps (`ios.sh`, `android.sh`)
- Every code change needs `build` before the app shows it: run `needs` after each edit; a fix loop
  costs a build per attempt, so batch the edits of one hypothesis before building.
- `needs` fingerprints every tracked and untracked file except `*.md` and `.claude/` — a new source
  file counts. `setup` (SETUP_CMD, e.g. `pod install`) is listed only when the context sets one.
- `force` rebuilds before relaunching: a forced state costs a build. Prefer a test-data helper or a
  launch argument the app already reads when one exists.

## Recording, evidence and publishing
- `$D video <name> [filter]` joins clips with AVFoundation (`scripts/join.swift`, fits 1920×1080;
  works without ffmpeg). `$D frame` grabs a still (`scripts/frame.swift`) to check a video isn't
  blank. Example sizes: 2 iOS steps → 10–22 s / 0.45 MB.
- `$D jpg` → half-size JPEG (0.2–3 MB PNG → 45–100 KB).
- `$D publish` → orphan branch `pr-assets/<TICKET>` via a temporary index (working tree and branch
  untouched), SHA-pinned `blob/<sha>/<file>?raw=true` URLs; re-running appends to the branch.
- Only steps named `ac*` are saved for the replay; `look-*`/unnamed steps are diagnostics.
- `replay` first deletes the previous replay's `ac*` shots, `ac<N>.mp4` and `workflow.mp4` (shots of a
  deleted flow would otherwise be published); forced shots (`*-forced*`) stay. A step that passes
  deletes its old `fail-<name>.png`.
- **Which device** (`$D status` prints the pick and why): iOS — `SIM_UDID` on the call > `IOS_UDID`
  (one machine) > `IOS_DEVICE` + `IOS_RUNTIME` from the context (by name, the same on every machine) >
  fallback: a booted simulator, one with the app installed first (`boot`: else the newest iPhone). The
  pick is kept in `.claude/work/.sim/ios-device`, so every call of a run uses the same simulator until
  `IOS_DEVICE` / `IOS_RUNTIME` change. Android — `SIM_SERIAL=<adb serial>` (another emulator or a
  physical device: screenshots only, no video) > the emulator running `ANDROID_AVD` > fallback: the
  first running emulator (`boot`: else the first AVD). A fallback may pick a simulator the user is
  using for something else: say which one at Preflight.
  `FORCE_SETTLE=<s>` sets how long `force` waits after relaunching.

## Verified
- 2026-10-21: `ios.sh` on an iPhone 15 simulator (iOS 17.0) against the Settings app: `boot`, `status`,
  `inspect`, passing `ac*` steps saved (~3 s each on a warm session), a failing step leaves
  `fail-<name>.png` and isn't saved, `defaults`, `logs`, and `replay` with screenshots + a joined
  `workflow.mp4` / `ac1.mp4`. `rn.sh` on the same simulator: `status`, `needs`, `step`, `reload`
  without Metro. The Android drivers have not been run on an emulator since the split.
- 2026-10-21, with stand-in `maestro` / `xcrun` / `adb`: the session survives a stale socket file and a
  failed `maestro` restart (reports it, recovers on the next call); an interrupted replay stops (exit
  130); `relaunch` and `force` exit codes follow the launch; Android picks the emulator running
  `ANDROID_AVD`; `boot` fails fast when the emulator dies; the driver's PATH keeps the user's node.
