#!/usr/bin/env bash
# Backend test surface: what the ticket changes behind the UI — HTTP/GraphQL APIs, the database, queues,
# jobs, caches — checked for AC verification. Every step writes a transcript (request or command,
# status, output, assertion, verdict) — the evidence for backend ACs.
# Usage: backend.sh <help|status|call|gql|sql|cmd|replay|report> [...]
#   call <name> <METHOD> <path> [json-body] [jq-assert]    e.g. call ac1-1-create POST /v1/items '{"a":1}' '.id != null'
#   gql  <name> '<query>' [variables-json] [jq-assert]     POST {query, variables} to API_GRAPHQL_PATH
#   sql  <name> '<query>' [regex-assert]                   runs DB_CMD (reads SQL on stdin)
#   cmd  <name> '<command>' [regex-assert]                 any other backend system: a queue, a job table
#                                                          tool, a cache, a log query (run from the repo root)
#   BACKEND_OUT evidence dir — required on every call (`help` excepted). Project values (API_URL,
#   API_GRAPHQL_PATH, API_AUTH_CMD, DB_CMD, BACKEND_RESET_CMD) come from the ```env block of the project
#   context (.claude/project-context.md, else the § Project context of AGENTS.md / CLAUDE.md; PROJECT_CONTEXT overrides).
#   API_AUTH_CMD prints one header line ("Authorization: Bearer …"); it is never written to transcripts.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../scripts/context.sh
. "$HERE/../../scripts/context.sh"
usage() { sed -n '2,/^set -uo/p' "$0" | sed '$d'; }
[ "${1:-help}" = help ] && { usage; exit 0; }
load_context
[ -n "${BACKEND_OUT:-}" ] || { echo "set BACKEND_OUT=<evidence dir> on this call: BACKEND_OUT=… $0 $1"; exit 2; }
OUT="$BACKEND_OUT"
mkdir -p "$OUT/flows"
REPLAYING="${BACKEND_REPLAYING:-0}"
RESET_CMD="${BACKEND_RESET_CMD:-${API_RESET_CMD:-}}"   # API_RESET_CMD: the name before the api surface became backend

save_flow() {
  # an ac* step that passed is saved as the exact command, for the evidence replay
  [[ "$1" == ac* ]] && [[ "$1" != *-forced ]] && [ "$REPLAYING" = 0 ] || return 0
  shift; { printf 'backend.sh'; printf ' %q' "$@"; echo; } > "$OUT/flows/$NAME.sh"; echo "saved: flows/$NAME.sh"
}

verdict() {
  # verdict <ok 0|1> <detail>: appends to the transcript and prints PASS/FAIL
  local res=PASS; [ "$1" = 1 ] || res=FAIL
  printf '\nResult: %s %s\n' "$res" "${2:-}" >> "$OUT/$NAME.txt"
  echo "$res $NAME ${2:-}"; [ "$res" = PASS ]
}

http() {
  # http <METHOD> <url> [body]: response body in $OUT/.body, status in $STATUS
  local data=(); [ -n "${3:-}" ] && data=(-H 'content-type: application/json' --data "$3")
  # ${a[@]+…}: macOS bash 3.2 treats an empty array as unbound under set -u
  rm -f "$OUT/.body"   # a failed request must not leave the previous step's body to assert on
  # A failing auth command must fail the step: inside a pipe its exit code was lost, and the request
  # went out unauthenticated — a step could pass without the auth it claims to test.
  local hdr=""
  if [ -n "${API_AUTH_CMD:-}" ]; then hdr=$(eval "$API_AUTH_CMD") || return 1; fi
  # the auth header reaches curl as config on stdin, so the token never shows in `ps` or a transcript
  STATUS=$({ [ -z "$hdr" ] || printf '%s\n' "$hdr" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/header = "/; s/$/"/'; } |
    curl -s -K - -o "$OUT/.body" -w '%{http_code}' -X "$1" ${data[@]+"${data[@]}"} "$2")
}

record_response() {
  printf 'Status: %s\n\n' "$STATUS" >> "$OUT/$NAME.txt"
  (jq . "$OUT/.body" || cat "$OUT/.body") 2>/dev/null | head -200 >> "$OUT/$NAME.txt"
}

assert_json() {
  # assert_json <jq-expr>: passes on HTTP 2xx and, when given, the expression being true
  [[ "$STATUS" == 2* ]] || { verdict 0 "(HTTP $STATUS)"; return 1; }
  [ -z "${1:-}" ] && { verdict 1; return 0; }
  printf '\nAssert: %s\n' "$1" >> "$OUT/$NAME.txt"
  [ "$(jq -r "$1" "$OUT/.body" 2>/dev/null)" = true ] && verdict 1 || { verdict 0 "(assertion false)"; return 1; }
}

assert_text() {
  # assert_text <exit code> <output> [regex]: passes on exit 0 and, when given, the output matching
  [ "$1" -eq 0 ] || { verdict 0 "(exit $1)"; return 1; }
  if [ -n "${3:-}" ]; then
    printf '\nAssert: matches /%s/\n' "$3" >> "$OUT/$NAME.txt"
    grep -Eq -- "$3" <<< "$2" || { verdict 0 "(no match)"; return 1; }
  fi
  verdict 1
}

case "${1:-status}" in
  status)
    echo "backend evidence: $OUT"
    echo "http: ${API_URL:-<API_URL unset>}"
    [ -n "${API_URL:-}" ] && curl -s -o /dev/null -w "reachable: HTTP %{http_code}\n" --max-time 5 "$API_URL" || true
    [ -n "${API_AUTH_CMD:-}" ] && echo "auth: API_AUTH_CMD set" || echo "auth: none (API_AUTH_CMD unset)"
    [ -n "${DB_CMD:-}" ] && echo "db: DB_CMD set" || echo "db: none (DB_CMD unset)"
    [ -n "$RESET_CMD" ] && echo "reset: BACKEND_RESET_CMD set" || echo "reset: none (BACKEND_RESET_CMD unset)"
    command -v jq >/dev/null || echo "jq: missing"
    ;;
  call)
    NAME="$2"; : "${API_URL:?API_URL missing in project context}"
    printf '%s %s\n' "$3" "$4" > "$OUT/$NAME.txt"; [ -n "${5:-}" ] && printf 'Body: %s\n' "$5" >> "$OUT/$NAME.txt"
    http "$3" "$API_URL$4" "${5:-}" || { verdict 0 "(API_AUTH_CMD failed)"; exit 1; }; record_response
    assert_json "${6:-}" && save_flow "$NAME" call "${@:2}"
    ;;
  gql)
    NAME="$2"; : "${API_URL:?API_URL missing in project context}"
    body=$(jq -nc --arg q "$3" --argjson v "${4:-null}" '{query:$q, variables:$v}') || { echo "variables are not valid JSON: ${4:-}"; exit 2; }
    printf 'POST %s (GraphQL)\n%s\nVariables: %s\n' "${API_GRAPHQL_PATH:-/graphql}" "$3" "${4:-null}" > "$OUT/$NAME.txt"
    http POST "$API_URL${API_GRAPHQL_PATH:-/graphql}" "$body" || { verdict 0 "(API_AUTH_CMD failed)"; exit 1; }; record_response
    # a GraphQL error comes back as HTTP 200 with "errors"
    if jq -e '.errors' "$OUT/.body" >/dev/null 2>&1; then verdict 0 "(GraphQL errors)"; exit 1; fi
    assert_json "${5:-}" && save_flow "$NAME" gql "${@:2}"
    ;;
  sql)
    NAME="$2"; : "${DB_CMD:?DB_CMD missing in project context}"
    printf 'SQL: %s\n\n' "$3" > "$OUT/$NAME.txt"
    out=$(printf '%s\n' "$3" | eval "$DB_CMD" 2>&1); rc=$?
    printf '%s\n' "$out" | head -200 >> "$OUT/$NAME.txt"
    assert_text "$rc" "$out" "${4:-}" && save_flow "$NAME" sql "${@:2}"
    ;;
  cmd)
    # the command is written to the transcript: secrets come from env or a token command, never inline
    NAME="$2"; : "${3:?usage: backend.sh cmd <name> '<command>' [regex-assert]}"
    printf 'Command: %s\n\n' "$3" > "$OUT/$NAME.txt"
    out=$(cd "$REPO" && eval "$3" 2>&1); rc=$?
    printf '%s\n' "$out" | head -200 >> "$OUT/$NAME.txt"
    assert_text "$rc" "$out" "${4:-}" && save_flow "$NAME" cmd "${@:2}"
    ;;
  replay)
    # evidence run: re-run every saved step in AC order, rewriting its transcript, then the report
    flows=(); while IFS= read -r f; do flows+=("$f"); done < <(ls "$OUT/flows"/*.sh 2>/dev/null | sort -V)
    [ ${#flows[@]} -gt 0 ] || { echo "no saved flows in $OUT/flows"; exit 1; }
    # steps that create data only replay cleanly from the same starting state
    if [ -n "$RESET_CMD" ]; then
      (cd "$REPO" && eval "$RESET_CMD") >"$OUT/reset.log" 2>&1 || { echo "BACKEND_RESET_CMD failed, see $OUT/reset.log: not replaying on a dirty state"; exit 1; }
      echo "state reset"
    fi
    failed=""
    for f in "${flows[@]}"; do
      n=$(basename "$f" .sh)
      # the first word is the driver name the flow was saved with; this driver runs it either way
      eval "BACKEND_REPLAYING=1 \"\$0\" $(cut -d' ' -f2- "$f")" || failed="$failed $n"
    done
    "$0" report
    [ -z "$failed" ] && echo "REPLAY: all steps passed" || { echo "REPLAY FAILED:$failed"; exit 1; }
    ;;
  report)
    # backend-evidence.md: one collapsible block per saved step (stale transcripts of abandoned steps are
    # left out), ready to paste into a PR or tracker comment
    {
      while IFS= read -r f; do
        t="$OUT/$(basename "$f" .sh).txt"; [ -f "$t" ] || continue
        n=$(basename "$t" .txt); r=$(grep -o 'Result: [A-Z]*' "$t" | tail -1 | cut -d' ' -f2)
        printf '<details><summary>%s — %s</summary>\n\n```\n' "$n" "${r:-?}"; cat "$t"; printf '```\n</details>\n\n'
      done < <(ls "$OUT/flows"/*.sh 2>/dev/null | sort -V)
    } > "$OUT/backend-evidence.md"
    echo "report: $OUT/backend-evidence.md"
    ;;
  *) usage; exit 2 ;;
esac
