# Visual check against the design — UI surfaces

`phases/test.md` §3.3 (and the Evidence recheck). How to look; the verdict categories are in test.md.

- Reach the state and take a `look-<state>` shot (never `ac…` — only evidence is published): mobile
  — `shot look-<state>`; web — end the `look-<state>` step itself with
  `await page.screenshot({ path: '<WEB_OUT>/look-<state>.png' })` (a web `shot` opens a fresh page,
  so it can't capture a state a step reached). Then
  `$SKILL/scripts/media.sh compare $W/design/<frame>.png <shot>.png` → `<shot>-vs-design.png`
  (design left, app right, same height) and check that one image (`SKILL.md` § Agent tools → image
  check; an agent that can't see images marks the state HUMAN). Missing frame → `screenshot(frame)`.
- Go through the checklist, top to bottom of the screen: **layout** (elements present, order,
  alignment) · **spacing and sizes** (scaled per the config's `frame_vs_device`; eyes can't tell
  4 from 8 px — check the code against `spec(frame)` for those) · **typography** (size, weight,
  case, truncation) · **colours** (the token the spec's variable maps to) · **icons** (right glyph,
  outline vs solid, stroke) · **copy** (exact, per the standing defaults) · **component states**
  (disabled, selected, pressed, focus) · **safe areas, keyboard, scroll end**.
- Ignore what isn't the design: content data (names, times, counts), status bar, OS-native sheets,
  dev-only overlays (LogBox, debug toasts), platform chrome the design doesn't draw.
