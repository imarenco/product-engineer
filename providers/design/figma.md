# Design provider — Figma (Figma MCP)

## Config keys (from `$CTX` § Design)
| Key | Example | Use |
|---|---|---|
| `files` | table: name → file key → what it holds | `find`, link resolution |
| `link_shape` | "a section of state frames, 375×812" | what a ticket link usually is |
| `frame_vs_device` | Figma 375×812 pt vs device sizes | comparing later |
| `mapping` | colours → tokens file; icons → assets dir; components → dirs/libraries; spacing → UI props | Design → code |
| `quirks` | file-specific behaviour (e.g. page listing incomplete) | all calls |

## Tools
Figma MCP tools (Claude Code: loaded with ToolSearch; `SKILL.md` § Agent tools) (`get_metadata`, `get_screenshot`, `get_design_context`,
`get_variable_defs`, `download_assets`, `search_design_system`). Load skill `figma:figma-design-to-code`
before the first `get_design_context`.

## resolve(link)
`figma.com/design/<fileKey>/<slug>?node-id=21222-117301` → `fileKey`, `nodeId: "21222:117301"` (dash →
colon). Branch URLs (`/design/<key>/branch/<branchKey>/`) use the branchKey. `/board/` = FigJam
(`get_figjam`), `/make/` = Make file (no metadata).

## list_states(node)
`get_metadata(fileKey, nodeId)` → the tree with ids, names and sizes. A section's child frames are the
state list. Always pass a nodeId — listing pages without one can be incomplete. A whole page can
overflow: the payload is saved to a file as `[{type,text}]` JSON — unwrap it with python before
grepping.

## screenshot(frame)
`get_screenshot(fileKey, nodeId: frameId, maxDimension: 1024)` → a short-lived URL; `curl` it to
`$W/design/<frame>.png` and Read it. Instance ids (`I…;…`) can't be screenshotted: use the parent frame.
The URL can't be fetched (sandbox, no network for curl) → call again with `enableBase64Response: true`
and look at the inline image (a small `maxDimension` keeps it light). No `$W/design/<frame>.png` then: compare by
viewing the frame and the `look-` shot yourself, and say in § Visual that this state has no side-by-side
image (Evidence skips its `-vs-design` file).

## spec(frame)
`get_design_context(fileKey, nodeId)` → real sizes, paddings, font size/weight, colours, component
names. Its code is a reference, never pasted. `get_variable_defs` when colours/typography are
variables — map them to the repo's tokens per `mapping`.

## assets(frame)
`download_assets` for icons the repo lacks; check outline vs solid and stroke width — a wrong variant
can render "identically wrong".

## find(screen or feature)
No link in the ticket: search the design files in `files` (`get_metadata` on the file's pages, then
the section whose name matches the feature), or `search_design_system` for components. Found nothing
→ a question for the user (ask for the link), never a guess.

## Verified
- 2026-10-16: the MCP can't see dev status (ready for dev / completed) — a frame that looks like an
  unapproved proposal is a question.
