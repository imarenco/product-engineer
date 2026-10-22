# Providers — the ticket system and the design system

The phases never name a tool. They call the **operations** below; the repo's project context
(`.claude/project-context.md`, else the § Project context of `AGENTS.md` / `CLAUDE.md`) says which provider to use and gives
its values:

```
## Tracker
provider: jira            ← loads providers/tracker/jira.md
<its config: site, ids, AC format, field ids, …>

## Design
provider: figma           ← loads providers/design/figma.md
<its config: file keys, how links look, design → code mapping, …>
```

Preflight step 2 loads both provider files; later phases use them. Its config keys are listed at the top of each provider file; a key the context doesn't give →
ask the user once and write it into the context (logged in `$W/context-updates.md`). A provider the skill doesn't have → read the closest
one as a model, do the same operations with the tool the user names, and offer to save it as a new
provider file.

## Tracker operations
| Operation | Returns / does | Used by |
|---|---|---|
| `get_ticket(key)` | summary, type, status, fix version, description, **ACs** (as the config's AC format says), comments, links, parent/epic, attachments, custom fields | Preflight (fix version, type), Ticket |
| `get_related(ticket)` | the linked + mentioned tickets, each via `get_ticket`, and its children / sub-tasks with their created date | Ticket, QA report (sub-bugs filed since) |
| `read_media(url)` | text of a video / doc / page attached or linked | Ticket |
| `set_field(key, field, value)` | writes a field the team expects when development is done; read it back | Ship |
| `comment(key, markdown)` | posts a comment — only with the user's OK | QA report, Ship (offer) |
| `transition(key, status)` | moves the ticket — only when the user asks | Ship (offer) |
| `branch_prefix(type)` | `feat` / `fix` / … from the issue type; a type mapped to `fix` is a bug ticket | Preflight (work branch), Ticket (bug triplets), Ship (fallback branch) |

## Design operations
| Operation | Returns / does | Used by |
|---|---|---|
| `resolve(link)` | the file and node a design link points at | Design |
| `list_states(node)` | the frames/screens under it, one per UI state, with names and sizes | Design |
| `screenshot(frame)` | a PNG in `$W/design/<frame>.png` (Evidence reuses these files) | Design, Test |
| `spec(frame)` | sizes, spacing, typography, colours (and their variables), component names | Design, Test (sizes eyes can't tell) |
| `assets(frame)` | icons/images to add when the repo has none that match | Design (mapping) |
| `find(screen or feature)` | where the design lives when the ticket has no link | Design |

## Writing a new provider
One file `providers/<tracker|design>/<name>.md` with: **Config keys** (what the context must give),
**Tools** (MCP server / CLI, how to load), one section per operation (the exact calls and their
quirks; an operation the tool can't do says how the phases degrade), and **Verified** (dated facts
learned the hard way). Keep repo-specific values out of it —
they belong in the context.
