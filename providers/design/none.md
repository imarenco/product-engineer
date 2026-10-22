# Design provider — none

For repos or tickets without design files (backend work, OS-native UI, a quick fix).

## Config keys
None. `frame_vs_device` and `mapping` don't apply: there are no frames.

- `resolve`, `list_states`, `screenshot`, `spec`, `assets`, `find`: none. The Design phase records
  "no design" and why.
- UI ACs then compare against: screenshots or images attached to the ticket, the existing app's
  current look (take a `look-` shot before changing anything), and the repo's design tokens. Any
  visual choice not dictated by those is an assumption shown at the plan gate.
