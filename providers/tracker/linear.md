# Tracker provider — Linear (Linear MCP, or the GraphQL API)

## Config keys (from `$CTX` § Tracker)
| Key | Example | Use |
|---|---|---|
| `workspace` | `acme` (linear.app/acme) | links |
| `access` | `mcp` (default) or `api` | which tool path below |
| `mcp` | tool prefix of the connected Linear server, e.g. `mcp__linear-server__` | loading tools |
| `api_key_cmd` | a command printing a Linear API key (keychain/env — never the key itself) | `access: api` |
| `teams` | team keys, e.g. `ENG`, `MOB` | key pattern, statuses |
| `key_pattern` | `(ENG\|MOB)-\d+` | finding mentioned issues |
| `ac_format` | e.g. `## Acceptance criteria` checklist in the description | where the ACs are |
| `read_also` | comments, project description, linked documents | intent the ACs omit |
| `fix_version` | what plays the role of a release: project, project milestone, cycle or label | Preflight base branch |
| `branch_prefix` | label `Bug` → `fix`, else `feat` (or use Linear's `branchName`, see below) | `branch_prefix(type)` |
| `done_fields` | what the team sets when development is done: a label, a status, a link attachment | `set_field` at Ship |
| `media_readers` | skills/tools for videos and docs | `read_media` |
| `standing_defaults` | gaps not worth asking | Ticket assumptions |

## Tools
- **MCP (default).** Linear's official remote server: `https://mcp.linear.app/mcp` (read-write) or
  `/mcp/readonly`. Setup (the user, once): `claude mcp add --transport http linear-server
  https://mcp.linear.app/mcp`, then `/mcp` to sign in (OAuth). Tool names are not documented by Linear:
  find them (Claude Code: with ToolSearch; other agents: their tool list) (`"linear issue"`, `"linear comment"`, `"linear status"`) and use the ones
  whose descriptions match each operation below. Not connected → tell the user the setup command; the
  skill can't run the OAuth flow itself.
- **API (`access: api`).** `POST https://api.linear.app/graphql` with header
  `Authorization: <key from api_key_cmd>` and a JSON `{query, variables}` body. Never write the key to
  a file or transcript.

## get_ticket(key)
MCP: the "get issue" tool with the identifier (`ENG-123`). API:
```graphql
query($id: String!) { issue(id: $id) {
  identifier title description url branchName priority estimate
  state { name type } labels { nodes { name } } assignee { name }
  project { name } projectMilestone { name } cycle { name number }
  parent { identifier title } children { nodes { identifier title state { name } } }
  relations { nodes { type relatedIssue { identifier title state { name } } } }
  comments { nodes { body createdAt user { name } } }
  attachments { nodes { title url } } } }
```
- ACs per `ac_format`; read every comment — product/QA decisions override the description.
- Type: Linear has no issue types — use labels (per `branch_prefix`).
- "Fix version": the field the config's `fix_version` names (project / milestone / cycle / label).

## get_related(ticket)
`parent`, `children`, `relations` (blocks, blocked by, related, duplicate) + every `key_pattern` match
and linear.app issue URL in description and comments → `get_ticket` each. The parent's project and
its description give the epic-level goal.

## read_media(url)
Attachments are links (Figma, Loom, GitHub, Docs): Figma → the design provider; videos → the
`media_readers`; Linear documents → the "get document" tool / `document(id)` query.

## set_field(key, field, value)
Linear has no free-form custom fields; `done_fields` maps to one of:
- label: MCP "update issue" with the label added / API `issueUpdate(id, input: {labelIds: [...]})`
  (keep the existing ones — the list replaces);
- status: see `transition`;
- a link (e.g. the demo video): MCP "create attachment" or a comment with the link / API
  `attachmentLinkURL(issueId, url, title)`.
Read it back with `get_ticket`. Already set to a real value → ask before replacing.

## comment(key, markdown)
MCP "create comment" / API `commentCreate(input: {issueId, body})` — only with the user's OK.

## transition(key, status)
List the team's workflow states (MCP "list issue statuses" / API `workflowStates(filter: {team:
{key: {eq: "ENG"}}})`), pick the one named `status`, then update the issue's state — only when the
user asks. Linking the PR (with the issue identifier in the branch or PR title) lets Linear's GitHub
integration move it automatically; prefer that.

## branch_prefix(type) and branch names
Linear suggests a branch per issue (`branchName`, e.g. `user/eng-123-short-title`); its GitHub
integration links PRs whose branch or title contains the identifier. Use `$CTX` § Git & PR's naming,
but keep the identifier in it so the link happens. The prefix: the issue's labels (from `get_ticket`)
mapped by the config's `branch_prefix`; no label matches → ask once.

## Verified
- 2026-10-17: every GraphQL field and mutation used above (Issue.identifier … attachments,
  `issueUpdate`, `commentCreate`, `attachmentLinkURL`, `issue`, `workflowStates`, `document`) exists in
  the live schema (checked by unauthenticated introspection of `api.linear.app/graphql`).
- Not yet run against a live workspace. Linear's MCP docs give the server URLs, setup and auth, but
  not tool names — confirm them on first use and note them here, dated.
