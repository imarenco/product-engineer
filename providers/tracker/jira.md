# Tracker provider — Jira (Atlassian MCP)

## Config keys (from `$CTX` § Tracker)
| Key | Example | Use |
|---|---|---|
| `site` | `acme.atlassian.net` | links, `/browse/<KEY>` |
| `cloudId` | UUID | every MCP call |
| `mcp` | `mcp__<atlassian server>__` | tool prefix to load (and any server to avoid) |
| `key_pattern` | `PROJ-\d+` | finding mentioned tickets |
| `ac_format` | `**AC #n:** blocks in the description`, and/or Gherkin `**Scenario 01:**` + Given/When/Then | where the ACs are |
| `read_also` | summary/value sections, every comment | intent the ACs omit |
| `branch_prefix` | `Bug → fix, else feat` | `branch_prefix(type)` |
| `done_fields` | `Demo video = customfield_NNNNN (URL)` | `set_field` at Ship |
| `media_readers` | Loom → a loom skill; video → a video skill | `read_media` |
| `standing_defaults` | gaps not worth asking | Ticket assumptions |

## Tools
Atlassian MCP tools, loaded with ToolSearch (`select:<mcp>getJiraIssue,…`). Pass `cloudId` on every
call. If a server answers 403 ("app not installed"), ask which Atlassian server to use and record its
prefix as `mcp`.

## get_ticket(key)
`getJiraIssue(cloudId, issueIdOrKey: key, view: "evidence")` → description (markdown), comments,
`issuelinks`, `parent`, `fixVersions`, `issuetype`, `status`, attachments and `customFields` by name.
- ACs: parse per `ac_format`; sub-bullets belong to their AC; duplicated AC numbers → a question.
  Gherkin: one AC per Scenario (title verbatim); its Given/When/Then already is the testable form —
  Given = state to reach, When = trigger, Then/And = the assertions. Zero ACs parsed from a ticket
  that has a description → check the other format before deriving any.
- Read every comment: product/QA decisions there override the description.
- `descriptionEditable: false` is a workflow lock on the description only, not on other fields.
- Inline `blob:` images in the description are not fetchable — say so.

## get_related(ticket)
`issuelinks[]` (inward/outward, with type: blocks, relates, clones…) + `parent` + subtasks + every
`key_pattern` match and `/browse/` URL in description and comments → `get_ticket` each (`view:
"compact"` is enough for context-only links).

## read_media(url)
Loom / Drive / attachment videos → the reader skills in `media_readers`. Confluence pages:
`getConfluenceContent(cloudId, content_url: <url>, detail: "full", content_format: "markdown")` (tiny
links `/wiki/x/…` work).

## set_field(key, field, value)
`editJiraIssue(cloudId, issueIdOrKey: key, additional_fields: {"<customfield_id>": value})` — field ids
from `done_fields`. Then `getJiraIssue(…, fields: ["<customfield_id>"])` and compare. A field already
holding a real value (not a placeholder) → ask before replacing.

## comment(key, markdown)
`addOrEditJiraIssueComment(cloudId, issueIdOrKey: key, body: markdown)` — only with the user's OK.

## transition(key, status)
`getTransitionsForJiraIssue` → pick the transition whose target is `status` → `transitionJiraIssue`.
Only when the user asks.

## branch_prefix(type)
`issuetype.name` from `get_ticket`, mapped by the config's `branch_prefix` (e.g. `Bug → fix, else
feat`). A type the mapping doesn't name → ask.

## Verified
- 2026-10-17: `editJiraIssue` with `additional_fields` set a URL custom field on a story whose
  `descriptionEditable` was false; `getJiraIssue` with `fields: [id]` read it back.
- 2026-10-17: `includeEditableFields` didn't return the editable-field list in `view: compact` — the
  only reliable permission check is the write itself (it fails cleanly without changes).
