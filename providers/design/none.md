# Design provider — none

For repos or tickets without design files (backend work, OS-native UI, a quick fix).

## Config keys
None. `frame_vs_device` and `mapping` don't apply: there are no frames.

- `resolve`, `list_states`, `screenshot`, `spec`, `assets`, `find`: none. The Design phase records
  "no design" and why.
- UI ACs then compare against: screenshots or images attached to the ticket, the existing app's
  current look, and the repo's design tokens. Any visual choice not dictated by those is an
  assumption shown at the plan gate.
- The current look is a baseline taken **before Code**, once the Preflight build is installed: per
  state an AC changes, reach it and shoot it, saved as `$W/design/current-<state>.png` (mobile
  `shot`, then move it there; web: the step's `page.screenshot`). Test's visual check uses it as the
  frame (`compare $W/design/current-<state>.png …`). A state that doesn't exist yet has no baseline:
  compare it against the tokens and the neighbouring screens, as an assumption. `--test-only`: there
  is no "before" (the installed build is the code under test) — compare against the tokens and the
  neighbouring screens, as an assumption.
