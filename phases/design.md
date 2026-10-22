# Phase 2 — Read the design

Goal: know exactly what every AC state must look like, and which existing tokens, icons and
components build it. Output: a `## Design` section in `$W/analysis.md` and frame images in `$W/design/`.

**Design provider.** `$CTX` § Design names it (`provider: figma`, …) and gives its config (files,
how links look, frame vs device sizes, design → code mapping). Use the operations of
`$SKILL/providers/design/<provider>.md` (Preflight already loaded it) — `resolve`, `list_states`,
`screenshot`, `spec`, `assets`, `find` (`providers/README.md`). No design for this ticket (backend
work, OS-native UI) or `provider: none` → record that and follow `providers/design/none.md`.

## 1. Find the design
- Links gathered in Phase 1 (ticket, comments, epic, sibling tickets) → `resolve` each.
- No link → `find(<screen or feature>)` in the provider's files. Nothing found → a question for the
  user (ask for the link), never a guess.

## 2. List and look at every state
- `list_states(node)`: a link often points at a group holding several frames/screens, one per state.
  The state names are the state list — map each to an AC; a state with no AC is a question, an AC with
  no state is a question.
- `screenshot(frame)` for every state relevant to an AC → `$W/design/<frame>.png`; Read each one.
- `spec(frame)` once per distinct layout you will build (states that only change copy or one element
  share the base layout's spec): real sizes, spacing, type, colours (variables), component names. It
  is a reference, never pasted code. With ≥ 2 distinct layouts, `spec` + the §3 mapping run as one
  subagent per layout in parallel (`SKILL.md` § Subagents); the screenshots you take and Read yourself.
- A state that looks like an unapproved proposal or contradicts another → a question.

## 3. Map design → code (per the provider config's `mapping` and the repo's architecture/styling rules)
- Colour → an existing token (new token only if none fits, named by role).
- Icon → an existing asset (grep by name, then look at it). Missing → `assets(frame)` and add it.
  Check variant (outline vs solid) and stroke width.
- Component → an existing one in the repo or its UI library before a new one.
- Typography/spacing → the UI library's props; note exact values.

## 4. Write the `## Design` section in `analysis.md`
```
## Design
Provider: <name> · source links: …
| State (id) | What it shows | AC(s) | Sizes, spacing, type | Colours → tokens | Icons → asset | Components reused |
Mismatches: AC says X / design shows Y · design shows Z that no AC covers · AC with no state
Links: | link | node | read / unreadable: <why> | states taken from it |
```
Every design link found in Phase 1 gets a row in Links — none dropped silently. An unreadable link
(no access, deleted node, `/make/` file) is a question at the plan gate: the plan never rests on a
design nobody looked at.
Mismatches go to "Questions for the user". Design elements no AC mentions are questions, not scope.

## Comparing later on the UI surfaces (used in Test, Review and Evidence)
- Design sizes rarely equal the device's (provider config `frame_vs_device`): compare proportions and
  spacing in points/dp, not pixel positions.
- Per element: exact copy and case, font weight, icon and variant, order, gaps, corner radius,
  colours, which elements are hidden in that state, keyboard presence.
