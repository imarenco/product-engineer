#!/usr/bin/env bash
# The run's changed files: tracked diff + untracked, never .claude/ or the context file.
#   changes.sh leftover <TICKET> [context file]  TEMPTEST / DEBUG-<TICKET> lines left in them (exit 1 if any), then git status
#   changes.sh fingerprint [context file]        a 12-char hash of HEAD + their contents: same hash = same code
set -uo pipefail
case "${1:-}" in
  leftover) TICKET="${2:?usage: changes.sh leftover <TICKET> [context file]}"; CTXF="${3:-}" ;;
  fingerprint) CTXF="${2:-}" ;;
  *) sed -n '2,4p' "$0"; exit 2 ;;
esac
ROOT="$(git rev-parse --show-toplevel)" || exit 2
cd "$ROOT" || exit 2
CTXF="${CTXF#"$ROOT"/}"

files() {
  # quotePath=false: git otherwise prints non-ASCII names quoted, and those files would be skipped
  { git -c core.quotePath=false diff --name-only HEAD; git -c core.quotePath=false ls-files --others --exclude-standard; } |
    grep -v -e '^\.claude/' | grep -vxF -- "${CTXF:-/}" | sort -u
}

if [ "$1" = leftover ]; then
  hits=$(files | while IFS= read -r f; do [ -f "$f" ] && grep -nHE "TEMPTEST|DEBUG-$TICKET" -- "$f"; done)
  if [ -n "$hits" ]; then echo "$hits"; echo "LEFTOVER: remove the lines above"; rc=1; else echo "leftover: none"; rc=0; fi
  echo "-- git status"; git status --short
  exit $rc
fi

# `rn.sh quiet on` adds a `// TEMPTEST quiet` line (LogBox off) for the whole device run; it changes no
# behaviour the gates check, so it must not make gate results stale. Every other line counts.
{ git rev-parse HEAD; files | while IFS= read -r f; do
    if [ -f "$f" ]; then
      h=$({ grep -v '// TEMPTEST quiet' -- "$f" || true; } | git hash-object --stdin)
      # changed only by the quiet line = unchanged: leave it out, as if it weren't in the diff
      [ "$h" = "$(git rev-parse -q --verify "HEAD:$f" 2>/dev/null)" ] || echo "$f $h"
    else echo "$f deleted"; fi; done; } |
  shasum | cut -c1-12
