# Tracker provider — none (the task comes in the conversation or a file)

For repos without a ticket system, or a quick task the user describes. The "ticket key" is a short
slug the user agrees to (e.g. `search-empty-state`), used for `$W` and branch names (`--automatic`: a
3–5-word kebab slug of the task's title, logged as an `auto:` decision).

## Config keys (from `$CTX` § Tracker)
| Key | Example | Use |
|---|---|---|
| `branch_prefix` | `feat` unless the user calls it a fix | `branch_prefix(type)`, bug triplets |
| `standing_defaults` | gaps not worth asking | Ticket assumptions |

- `get_ticket`: the user's message, or a file they point at (a spec, a plan, an issue export). ACs:
  the explicit acceptance criteria if any; otherwise derive them from the description and mark each
  `DERIVED` — the plan gate shows them for approval.
- `get_related`, `read_media`: only what the user links; no children (the QA log is the only record
  of sub-bugs).
- `set_field`, `comment`, `transition`: none — the report says so. A `qa_share: ticket comment`
  falls back to keeping the QA report local.
- `branch_prefix`: ask once (`feat` / `fix`), per `$CTX` § Git & PR.
