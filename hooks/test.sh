#!/usr/bin/env bash
# Checks for both hooks. Run from anywhere:  bash hooks/test.sh
# Every case runs in a throwaway repository with HOME pointed at a throwaway
# folder, so nothing of yours is read or written.

PACK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0
fail=0

check() { # $1 label  $2 expected exit  $3 actual exit
  if [ "$2" = "$3" ]; then
    echo "  PASS  $1 (exit $3)"
    pass=$((pass + 1))
  else
    echo "  FAIL  $1 (expected $2, got $3)"
    fail=$((fail + 1))
  fi
}

newrepo() {
  W="$(mktemp -d)"
  cd "$W" || exit 1
  git init -q
  echo a > a.txt
  git add .
  git -c user.name=t -c user.email=t@t commit -qm init
}

start() { printf '{"session_id":"%s"}' "$1" | HOME="$H" bash "$PACK/hooks/session-start.sh" >/dev/null 2>&1; }
stop() { printf '{"session_id":"%s"}' "$1" | HOME="$H" bash "$PACK/hooks/stop-report.sh" 2>/dev/null; }

echo "CASE 1  work finished in one reply, with the baseline"
H="$(mktemp -d)"; newrepo
start S1
echo change >> a.txt
stop S1; check "asks for a report" 2 $?

echo "CASE 2  baseline taken, nothing changed after it"
H="$(mktemp -d)"; newrepo
start S2
stop S2; check "stays silent" 0 $?

echo "CASE 3  the tree was already dirty before the session"
H="$(mktemp -d)"; newrepo
echo "someone else's edit" >> a.txt
start S3
stop S3; check "stays silent" 0 $?

echo "CASE 4  SessionStart fires again mid-session (compact, clear)"
start S3
echo change >> a.txt
export OPEN_STEPS_COOLDOWN=0
stop S3; check "the pending report survives" 2 $?
stop S3; check "the next stop is silent, no loop" 0 $?
unset OPEN_STEPS_COOLDOWN

echo "CASE 5  fallback: the SessionStart hook never ran"
H="$(mktemp -d)"; newrepo
export OPEN_STEPS_COOLDOWN=0
echo change >> a.txt
stop S5; check "the first stop only takes a baseline" 0 $?
echo more >> a.txt
stop S5; check "the second stop asks" 2 $?
unset OPEN_STEPS_COOLDOWN

echo "CASE 6  the kill switch"
H="$(mktemp -d)"; newrepo
start S6
echo change >> a.txt
OPEN_STEPS_DISABLE=1 stop S6; check "silent when switched off" 0 $?

echo "CASE 7  no repository anywhere"
H="$(mktemp -d)"; D="$(mktemp -d)"; cd "$D" || exit 1
start S7
echo hello > note.txt
stop S7; check "stays silent" 0 $?

echo "CASE 8  the handover the SessionStart hook prints"
H="$(mktemp -d)"; newrepo
out="$(printf '{"session_id":"S8"}' | HOME="$H" bash "$PACK/hooks/session-start.sh" 2>/dev/null)"
case "$out" in
  *"<session-handover>"*os-done-or-not*"</session-handover>"*) check "the routing table is intact" 0 0 ;;
  *) check "the routing table is intact" 0 1 ;;
esac
case "$out" in
  *OS_STATE_*) check "the baseline stays off stdout" 0 1 ;;
  *) check "the baseline stays off stdout" 0 0 ;;
esac

echo "CASE 9  a payload from another agent, with fields these hooks do not know"
# Codex and Gemini CLI send the same session_id inside a fuller payload. The
# baseline is taken from a plain one and the stop reads the fuller one, so a
# session id that failed to parse would fall back, stop matching, and this case
# would go silent instead of asking. That is what makes it worth a case.
H="$(mktemp -d)"; newrepo
start S9
echo change >> a.txt
printf '{"session_id":"S9","cwd":"%s","transcript_path":null,"model":"gpt-5","permission_mode":"default"}' "$PWD" \
  | HOME="$H" bash "$PACK/hooks/stop-report.sh" 2>/dev/null
check "the session id is still found" 2 $?

echo "CASE 10  Cursor: JSON both ways, and a stop that cannot block"
# Cursor answers only to JSON on stdout and cannot block a stop, so the adapter
# wraps the handover as additional_context and turns the report request into a
# followup_message. Its stop payload carries no session_id, only
# conversation_id, so the adapter keys both events on that: a stop that still
# looked for session_id would take a fresh baseline instead of asking.
# CURSOR_PROJECT_DIR is set on every call because Cursor always sets it and
# the adapter follows it; left to the environment, a suite run from inside a
# hook would measure some other repository.
H="$(mktemp -d)"; newrepo
# A previous report with the characters JSON cannot carry raw. The routing
# table has none of them, so without this the escaping is never exercised.
mkdir -p "$H/.claude/open-steps/reports/$(basename "$PWD")"
printf '%s\n' 'path C:\Users \"quoted\" \d' > "$H/.claude/open-steps/reports/$(basename "$PWD")/latest.md"
cstart="$(printf '{"conversation_id":"C10","generation_id":"g1","hook_event_name":"sessionStart","session_id":"S10","workspace_roots":["%s"]}' "$PWD")"
out="$(printf '%s' "$cstart" | HOME="$H" CURSOR_PROJECT_DIR="$PWD" bash "$PACK/hooks/adapter.sh" cursor session-start 2>/dev/null)"
case "$out" in
  '{"additional_context":"'*"<session-handover>"*os-done-or-not*'"}') check "the handover arrives as additional_context" 0 0 ;;
  *) check "the handover arrives as additional_context" 0 1 ;;
esac
[ "$(printf '%s' "$out" | wc -l | tr -d ' ')" = "0" ]; check "on one line, newlines escaped" 0 $?
printf '%s' "$out" | grep -Fq 'path C:\\Users \\\"quoted\\\" \\d' ; check "backslashes doubled and quotes escaped" 0 $?
echo change >> a.txt
cstop='{"conversation_id":"C10","generation_id":"g2","hook_event_name":"stop","status":"aborted","loop_count":0}'
out="$(printf '%s' "$cstop" | HOME="$H" CURSOR_PROJECT_DIR="$PWD" bash "$PACK/hooks/adapter.sh" cursor stop 2>/dev/null)"
[ "$out" = "{}" ]; check "an aborted stop is left alone" 0 $?
cstop='{"conversation_id":"C10","generation_id":"g3","hook_event_name":"stop","status":"completed","loop_count":0}'
out="$(printf '%s' "$cstop" | HOME="$H" CURSOR_PROJECT_DIR="$PWD" bash "$PACK/hooks/adapter.sh" cursor stop 2>/dev/null)"
code=$?
case "$out" in
  '{"followup_message":"Work landed'*os-done-or-not*'"}') check "a completed stop asks through followup_message" 0 0 ;;
  *) check "a completed stop asks through followup_message" 0 1 ;;
esac
check "with exit 0, since 2 cannot block here" 0 $code
# Parsed by a real interpreter where one exists, since the shape checks above
# cannot see a bad escape. Skipped, not failed, where there is none.
py=""
for cand in python3 python; do
  command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import json' >/dev/null 2>&1 && { py="$cand"; break; }
done
if [ -n "$py" ]; then
  printf '%s' "$out" | "$py" -c 'import json, sys; json.load(sys.stdin)' 2>/dev/null
  check "and it parses as JSON" 0 $?
fi
out="$(printf '%s' "$cstop" | HOME="$H" CURSOR_PROJECT_DIR="$PWD" bash "$PACK/hooks/adapter.sh" cursor stop 2>/dev/null)"
[ "$out" = "{}" ]; check "the next stop is silent, no loop" 0 $?

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
