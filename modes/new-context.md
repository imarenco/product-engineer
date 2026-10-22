# New project context — the repo has none yet

Read it in Preflight step 1 when no `$CTX` is found. `--automatic` never builds one: it stops
(`modes/automatic.md`).

Build it before anything else, from `$SKILL/templates/project-context.md`, as
`.claude/project-context.md` (read only when this skill runs, unlike `AGENTS.md`, which every session
loads). When `git check-ignore -q .claude/project-context.md` succeeds it would stay on this machine:
ask — add `!.claude/project-context.md` to `.gitignore` / keep it local / a `## Project context`
section in `AGENTS.md` instead (its `##` headings demoted to `###`).

Fill what the repo shows: package.json / build files, `AGENTS.md` / `CLAUDE.md`, `git remote`,
`gh pr list --limit 5`, `xcrun simctl list` (→ `IOS_DEVICE` by name, not a UDID: the context is
shared), `emulator -list-avds`, the MCP servers available. Ask the rest in one or two questions
(ticket system, design system, base-branch rule, PR conventions), save it, and recommend the user
commits it on its own, outside the ticket's PR — an uncommitted context is noise in every later
`git status`.
