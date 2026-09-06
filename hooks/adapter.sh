#!/usr/bin/env bash
# Adapter for tools that want JSON on stdout where the two hooks print text.
# One copy of the hook logic: this script runs session-start.sh or
# stop-report.sh unchanged and only translates what goes in and what comes out.
#
#   adapter.sh cursor session-start     wraps the handover as additional_context
#   adapter.sh cursor stop              asks for the report as followup_message
#
# Cursor's contract, the parts that matter here:
# - Both events must answer with JSON; anything else counts as a hook failure.
# - A stop cannot be blocked. The one thing it can do is hand Cursor a
#   followup_message, which Cursor submits as the next user message, at most
#   loop_limit times per conversation (5 unless configured).
# - The stop payload has no session_id, only conversation_id. The baseline is
#   keyed by session, so both events use conversation_id here, or the stop
#   would never find the baseline the start took.
# - A stop reports its status. Only a completed stop is asked for a report:
#   after an abort or an error the change stays pending for the next one,
#   and nobody gets an unrequested message submitted on their behalf.
#
# The settings and kill switches of the two scripts apply unchanged, because
# the scripts read them, not this adapter.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tool="${1:-}"
event="${2:-}"

usage() {
  printf 'usage: adapter.sh cursor session-start|stop\n' >&2
  exit 1
}

[ "$tool" = "cursor" ] || usage
case "$event" in session-start|stop) ;; *) usage ;; esac

payload="$(cat 2>/dev/null || true)"

# One string field out of a flat JSON payload, the same way fingerprint.sh
# reads session_id. Good enough for the identifiers these tools send.
field() { # $1 = key
  printf '%s' "$payload" \
    | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" \
    | head -1 | sed -E 's/.*"([^"]+)"$/\1/'
}

# A JSON string literal, quotes included. Control characters other than
# newline, tab and return are dropped rather than escaped: none of them can
# appear in what these hooks print. Backslash and quote go through sed, not
# bash's own substitution, because bash 3.2 (macOS /bin/bash) reads a quoted
# replacement differently from bash 4.3 and later and would leave the
# backslash single. LC_ALL=C so a stray non-UTF-8 byte is passed through
# rather than making tr stop early.
json_string() { # $1 = text
  local s
  s="$(printf '%s' "$1" \
    | LC_ALL=C tr -d '\000-\010\013\014\016-\037' \
    | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  printf '"%s"' "$s"
}

# The hooks look for the repository from the working directory. Cursor sets
# CURSOR_PROJECT_DIR on every hook; use it when it is there.
[ -n "${CURSOR_PROJECT_DIR:-}" ] && cd "$CURSOR_PROJECT_DIR" 2>/dev/null

# The session id the hooks will see: conversation_id, present on both events.
id="$(field conversation_id)"
[ -n "$id" ] || id="$(field session_id)"
inner="$(printf '{"session_id":"%s"}' "$id")"

case "$event" in
  session-start)
    out="$(printf '%s' "$inner" | bash "$HERE/session-start.sh" 2>/dev/null || true)"
    if [ -n "$out" ]; then
      printf '{"additional_context":%s}\n' "$(json_string "$out")"
    else
      printf '{}\n'
    fi
    ;;
  stop)
    status="$(field status)"
    if [ -n "$status" ] && [ "$status" != "completed" ]; then
      printf '{}\n'
      exit 0
    fi
    err="$(printf '%s' "$inner" | bash "$HERE/stop-report.sh" 2>&1 >/dev/null)"
    code=$?
    # Cursor submits this text as the person's own next message, so only the
    # report request goes through: anything bash printed before it (a bad
    # state file, say) stays out. The request starts with "Work landed".
    ask="$(printf '%s\n' "$err" | sed -n '/^Work landed/,$p')"
    [ -n "$ask" ] || ask="$err"
    if [ "$code" -eq 2 ] && [ -n "$ask" ]; then
      printf '{"followup_message":%s}\n' "$(json_string "$ask")"
    else
      printf '{}\n'
    fi
    ;;
esac

exit 0
