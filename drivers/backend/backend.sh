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
#   API_GRAPHQL_PATH, API_AUTH_CMD, API_TIMEOUT (seconds, default 60), DB_CMD, BACKEND_RESET_CMD) come from the ```env block of the project
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
mkdir -p "$OUT/flows" && OUT="$(cd "$OUT" && pwd)"   # absolute: a relative dir breaks once a step cd's
REPLAYING="${BACKEND_REPLAYING:-0}"
RESET_CMD="${BACKEND_RESET_CMD:-${API_RESET_CMD:-}}"   # API_RESET_CMD: the name before the api surface became backend

save_flow() {
  # an ac* step that passed is saved as the exact command, for the evidence replay
  [[ "$1" == ac* ]] && [[ "$1" != *-forced ]] && [ "$REPLAYING" = 0 ] || return 0
  shift; { printf 'backend.sh'; printf ' %q' "$@"; echo; } > "$OUT/flows/$NAME.sh"; echo "saved: flows/$NAME.sh"
}

need() { [ "$1" -ge "$2" ] || { echo "usage: backend.sh $3"; exit 2; }; }

verdict() {
  # verdict <ok 0|1> <detail>: appends to the transcript and prints PASS/FAIL
  local res=PASS; [ "$1" = 1 ] || res=FAIL
  printf '\nResult: %s %s\n' "$res" "${2:-}" >> "$OUT/$NAME.txt"
  echo "$res $NAME ${2:-}"
  if [ "$res" = FAIL ]; then
    # enough to diagnose without opening the transcript: its path and the start of what came back
    echo "  transcript: $OUT/$NAME.txt"
    # awk, not sed: it ends every line, even a body with no final newline
    if [ -s "$OUT/.body" ]; then head -c 600 "$OUT/.body" | head -5 | awk '{print "  | " $0}'
    elif [ -n "${LAST_OUT:-}" ]; then printf '%s\n' "$LAST_OUT" | head -5 | awk '{print "  | " $0}'; fi
  fi
  [ "$res" = PASS ]
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
  # A server that is down or too slow is HTTP 000, reported by assert_json — not an auth failure:
  # only the auth command's failure above returns 1. --max-time: a stuck API must not hang the step.
  STATUS=$({ [ -z "$hdr" ] || printf '%s\n' "$hdr" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/header = "/; s/$/"/'; } |
    curl -s -K - --max-time "${API_TIMEOUT:-60}" -o "$OUT/.body" -w '%{http_code}' -X "$1" ${data[@]+"${data[@]}"} "$2")
  CURL_RC=$?
  return 0
}

# HTTP 000 = no response at all: say why (curl's exit code), a timeout isn't a server that's down
no_response() {
  case "${CURL_RC:-0}" in
    28) echo "no response: timed out after ${API_TIMEOUT:-60}s" ;;
    7) echo "no response: connection refused" ;;
    6) echo "no response: host not found" ;;
    *) echo "no response: curl exit ${CURL_RC:-?}" ;;
  esac
}

record_response() {
  printf 'Status: %s%s\n\n' "$STATUS" "$([ "$STATUS" = 000 ] && echo " ($(no_response))")" >> "$OUT/$NAME.txt"
  (jq . "$OUT/.body" || cat "$OUT/.body") 2>/dev/null > "$OUT/.pretty"
  head -200 "$OUT/.pretty" >> "$OUT/$NAME.txt"
  n=$(wc -l < "$OUT/.pretty" | tr -d ' '); [ "$n" -gt 200 ] && printf '… truncated: %s lines in all\n' "$n" >> "$OUT/$NAME.txt"
  rm -f "$OUT/.pretty"
}

assert_json() {
  # assert_json <jq-expr>: passes on HTTP 2xx and, when given, the expression being true
  [ "$STATUS" = 000 ] && { verdict 0 "($(no_response))"; return 1; }
  [[ "$STATUS" == 2* ]] || { verdict 0 "(HTTP $STATUS)"; return 1; }
  [ -z "${1:-}" ] && { verdict 1; return 0; }
  printf '\nAssert: %s\n' "$1" >> "$OUT/$NAME.txt"
  local v jrc; v=$(jq -r "$1" "$OUT/.body" 2>"$OUT/.jqerr"); jrc=$?
  # a broken expression is not a false assertion: say which
  [ $jrc -eq 0 ] || { verdict 0 "(jq error: $(head -1 "$OUT/.jqerr"))"; return 1; }
  [ "$v" = true ] && verdict 1 || { verdict 0 "(assertion false)"; return 1; }
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
    need $# 4 "call <name> <METHOD> <path> [json-body] [jq-assert]"; NAME="$2"
    : "${API_URL:?API_URL missing in project context}"
    # a jq assertion put in the body slot would be sent as the body and the step would pass unasserted
    [ -z "${5:-}" ] || jq . >/dev/null 2>&1 <<<"$5" || { echo "body is not valid JSON: $5 (the jq assertion goes after the body; no body → '')"; exit 2; }
    printf '%s %s\n' "$3" "$4" > "$OUT/$NAME.txt"; [ -n "${5:-}" ] && printf 'Body: %s\n' "$5" >> "$OUT/$NAME.txt"
    http "$3" "$API_URL$4" "${5:-}" || { verdict 0 "(API_AUTH_CMD failed)"; exit 1; }; record_response
    assert_json "${6:-}" && save_flow "$NAME" call "${@:2}"
    ;;
  gql)
    need $# 3 "gql <name> '<query>' [variables-json] [jq-assert]"; NAME="$2"
    : "${API_URL:?API_URL missing in project context}"
    body=$(jq -nc --arg q "$3" --argjson v "${4:-null}" '{query:$q, variables:$v}') || { echo "variables are not valid JSON: ${4:-}"; exit 2; }
    printf 'POST %s (GraphQL)\n%s\nVariables: %s\n' "${API_GRAPHQL_PATH:-/graphql}" "$3" "${4:-null}" > "$OUT/$NAME.txt"
    http POST "$API_URL${API_GRAPHQL_PATH:-/graphql}" "$body" || { verdict 0 "(API_AUTH_CMD failed)"; exit 1; }; record_response
    # a GraphQL error comes back as HTTP 200 with "errors"
    if jq -e '.errors' "$OUT/.body" >/dev/null 2>&1; then verdict 0 "(GraphQL errors)"; exit 1; fi
    assert_json "${5:-}" && save_flow "$NAME" gql "${@:2}"
    ;;
  sql)
    need $# 3 "sql <name> '<query>' [regex-assert]"; NAME="$2"
    : "${DB_CMD:?DB_CMD missing in project context}"
    printf 'SQL: %s\n\n' "$3" > "$OUT/$NAME.txt"
    rm -f "$OUT/.body"; out=$(printf '%s\n' "$3" | eval "$DB_CMD" 2>&1); rc=$?; LAST_OUT="$out"
    printf '%s\n' "$out" | head -200 >> "$OUT/$NAME.txt"
    n=$(printf '%s\n' "$out" | wc -l | tr -d ' '); [ "$n" -gt 200 ] && printf '… truncated: %s lines in all\n' "$n" >> "$OUT/$NAME.txt"
    assert_text "$rc" "$out" "${4:-}" && save_flow "$NAME" sql "${@:2}"
    ;;
  cmd)
    # the command is written to the transcript: secrets come from env or a token command, never inline
    need $# 3 "cmd <name> '<command>' [regex-assert]"; NAME="$2"
    printf 'Command: %s\n\n' "$3" > "$OUT/$NAME.txt"
    rm -f "$OUT/.body"; out=$(cd "$REPO" && eval "$3" 2>&1); rc=$?; LAST_OUT="$out"
    printf '%s\n' "$out" | head -200 >> "$OUT/$NAME.txt"
    n=$(printf '%s\n' "$out" | wc -l | tr -d ' '); [ "$n" -gt 200 ] && printf '… truncated: %s lines in all\n' "$n" >> "$OUT/$NAME.txt"
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
