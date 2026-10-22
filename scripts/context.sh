# Sourced by the drivers: finds the project context and loads its ```env block.
# The context is a dedicated .claude/project-context.md if the repo has one, else the "## Project context"
# section of AGENTS.md / CLAUDE.md. PROJECT_CONTEXT overrides the location.
# the repo of the current folder; outside one, the repo PROJECT_CONTEXT lives in; else the folder itself
REPO="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" \
  || REPO="$( [ -n "${PROJECT_CONTEXT:-}" ] && git -C "$(dirname "$PROJECT_CONTEXT")" rev-parse --show-toplevel 2>/dev/null )" \
  || REPO="$(pwd)"
CONTEXT="${PROJECT_CONTEXT:-}"
if [ -z "$CONTEXT" ]; then
  # same order as SKILL.md: the dedicated file, else the "## Project context" section of AGENTS.md / CLAUDE.md
  if [ -f "$REPO/.claude/project-context.md" ]; then CONTEXT="$REPO/.claude/project-context.md"
  else
    for c in "$REPO/AGENTS.md" "$REPO/CLAUDE.md"; do
      [ -f "$c" ] && grep '^## Project context' "$c" >/dev/null && { CONTEXT="$c"; break; }
    done
  fi
fi

# load_context: assigns each KEY=value line of the ```env block(s). A value already set on the call
# (e.g. `API_URL=http://localhost:4000 backend.sh …`) wins over the file. CRLF files are handled. The repo's
# own context is trusted config — but only call this after `help`, so reading usage runs nothing.
load_context() {
  [ -f "${CONTEXT:-}" ] || return 0
  local line key
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    key="${line%%=*}"
    case "$key" in ''|*[!A-Za-z0-9_]*) continue ;; esac
    eval "[ -n \"\${$key+x}\" ]" && continue
    eval "$line"
  done < <(awk '{sub(/\r$/,"")} /^```env[[:space:]]*$/{f=1;next} /^```/{f=0} f' "$CONTEXT")
}
