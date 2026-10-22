# Tracker provider — GitHub Issues (`gh` CLI)

## Config keys (from `$CTX` § Tracker)
| Key | Example | Use |
|---|---|---|
| `repo` | `owner/name` (default: the current repo) | every call |
| `key_pattern` | `#\d+` | finding mentioned issues |
| `ac_format` | `- [ ] task-list items under "## Acceptance criteria"` | where the ACs are |
| `read_also` | e.g. linked discussion, PR review comments | intent the ACs omit |
| `branch_prefix` | label `bug` → `fix`, else `feat` | `branch_prefix(type)` |
| `done_fields` | e.g. a label or a project field to set | `set_field` at Ship |
| `media_readers` | skills/tools for videos and docs | `read_media` |
| `standing_defaults` | gaps not worth asking | Ticket assumptions |

## Tools
The `gh` CLI, authenticated (`gh auth status`). Not logged in → the user runs `gh auth login`; the
skill can't do it. No MCP needed.

## get_ticket(key)
`gh issue view <n> -R <repo> --json number,title,body,labels,state,milestone,comments,assignees,url`
— the milestone plays the role of a fix version; labels give the type. ACs per `ac_format`.

## get_related(ticket)
Every `#n` / issue URL in body and comments, plus `gh issue develop --list <n>` (linked branches) and
the issue's sub-issues/tracked-by when the repo uses them → `get_ticket` each.

## read_media(url)
Attached images/videos are user-attachment URLs: download with `gh` auth only when needed; videos →
a video-reader skill if the context names one.

## set_field / comment / transition
- `set_field`: labels `gh issue edit <n> --add-label …`; project fields via `gh project item-edit`.
- `comment`: `gh issue comment <n> --body-file <file>` — only with the user's OK.
- `transition`: `gh issue close <n>` / reopen — only when the user asks (PRs usually close issues with
  `Closes #n` in the PR body instead).

## branch_prefix(type)
GitHub issues have no type field (unless the org uses issue types): the labels from `get_ticket`,
mapped by the config's `branch_prefix`. No matching label → ask.

## Verified
- Not yet run against a live repo with this skill — confirm the calls on first use and note them
  here, dated.
