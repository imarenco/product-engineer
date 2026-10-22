# React Native — `drivers/react-native/rn.sh`

What only React Native apps need, on top of `references/mobile.md` (read that first: Maestro,
simulators, the shared commands). Pass `SIM_PLATFORM=<ios|android> SIM_OUT=$W/shots/<platform>`
on every call.

| Need | Command |
|---|---|
| start the bundler (non-interactive shells don't auto-start it) | `rn.sh metro` — resets its cache by itself after a branch or dependency change; `rn.sh metro reset` forces it |
| JS change / stale screen | `rn.sh reload` / `rn.sh relaunch [seconds]` |
| LogBox toasts off / back on (Debug builds) | `rn.sh quiet on` / `rn.sh quiet off` (a `TEMPTEST quiet` line in `index.js`; relaunch to apply) |
| app state (MMKV) | `rn.sh mmkv <key-substring> [n]` (`IOS_STATE_FILE` / `ANDROID_STATE_FILE` in the context) |
| JS logs (Android only) | `rn.sh logs <text>` (logcat tag ReactNativeJS) |

## Builds and Metro
- `needs` treats `ios/`, `android/` and the dependency manifests as native: a JS-only change needs
  no `build` — the installed Debug app loads it from Metro. Any manifest or lockfile change counts
  as native (a JS-only dependency bump costs a rebuild it didn't need).
- An installed app whose `main.jsbundle` is Hermes bytecode (`file <app>/main.jsbundle`) is a
  Release-style build: it never loads JS from Metro, so edits, `reload` and Fast Refresh do nothing.
  Fine for testing the commit it was built from; `build` a Debug app before testing uncommitted
  changes. Check it at Preflight.
- Android reaches the bundler through `adb reverse tcp:<port>` (`build` and `relaunch` set it).
  After a Metro cache reset, the first Android bundle takes minutes; the app sits on the splash.
- Never pipe `rn.sh metro` into `tail`/`grep` in a chain (`setup; metro | tail; build`): Metro keeps
  the pipe open, so the chain hangs after "metro: up". Run `metro` unpiped and poll
  `curl localhost:<port>/status`.
- After `setup` (npm ci) the app can show "Unable to resolve module @babel/runtime/…" with the file
  on disk: stale watchman. `watchman watch-del-all`, restart Metro, relaunch.
- `npm ci` fails with ENOTEMPTY while a Gradle daemon holds `node_modules`: `setup` stops Metro and
  Gradle daemons first.
- A `git checkout -- <file>` after `pod install` (pbxproj churn) changes the native fingerprint, so
  `needs` asks for a rebuild the installed app doesn't need — `build` is the safe answer.

## Testing
- `quiet on/off` edits `index.js` → Metro reloads the app back to its first tab: run `quiet` before
  navigating, never mid-test, and `quiet off` before the leftover check.
- React Native 0.81 JS logs reach neither `simctl log` nor Metro's log on iOS — probe state with
  `mmkv` (or the backend) instead; Android JS logs reach logcat (`rn.sh logs`).
- `mmkv` lists every write to the matching keys, oldest first; the last one is the live value (MMKV
  appends). Single-byte values print as numbers (`0` = false or empty string).
- ScrollViews inside an RN `Modal` don't scroll under Maestro → HUMAN, or tap by point.
- `force` edits `const|let NAME = …; // TEMPTEST` lines and relaunches; Metro serves the edit, no
  rebuild.
