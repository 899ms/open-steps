#!/usr/bin/env bash
# Checks for the measurement scripts. Run from anywhere:  bash evals/test.sh
# Nothing here talks to a model. The scorer reads the hand-made streams in
# fixtures/, and the runner is driven with a stand-in `claude` on PATH that
# writes down what it was asked and answers with a two-line stream. HOME points
# at a throwaway folder, so nothing of yours is read or written.

PACK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0
fail=0

check() { # $1 label  $2 expected  $3 actual
  if [ "$2" = "$3" ]; then
    echo "  PASS  $1"
    pass=$((pass + 1))
  else
    echo "  FAIL  $1 (expected '$2', got '$3')"
    fail=$((fail + 1))
  fi
}
score() { python3 "$PACK/evals/score.py" --print "$PACK/evals/fixtures/$1" 2>&1; }
has() { printf '%s' "$1" | grep -qF -- "$2" && echo yes || echo no; }

echo "CASE 1  a denied Skill call still counts as the model's choice"
out="$(score permission-denied)"
# shellcheck disable=SC2016  # the backticks are markdown, matched as text
check "os-done-or-not scores 1/1" yes "$(has "$out" '| `os-done-or-not` | 1/1 |')"

echo "CASE 2  a quality arm whose every Skill call was denied is not a measurement"
out="$(score quality-denied)"
check "says the arm was not measured" yes "$(has "$out" 'not measured')"
check "prints no with row for it" no "$(has "$out" '| Haiku 4.5 | with')"
check "counts the streams that still carried the messaging tools" yes \
  "$(has "$out" 'sealed off from other sessions (no SendMessage or ListAgents tool): 0 of 2')"

echo "CASE 3  a quality arm where one Skill call ran is measured, matched by id"
out="$(score quality-measured)"
check "prints the with row" yes "$(has "$out" '| Haiku 4.5 | with |')"
check "does not call it unmeasured" no "$(has "$out" 'not measured')"
check "counts the sealed streams" yes \
  "$(has "$out" 'sealed off from other sessions (no SendMessage or ListAgents tool): 2 of 2')"

echo "CASE 4  the runner seals every run and lets the quality arm load a skill"
H="$(mktemp -d)"
STUB="$(mktemp -d)"
export STUB_LOG="$STUB/calls.log"
cat > "$STUB/claude" <<'STUB'
#!/usr/bin/env bash
# Stand-in for the CLI: one line per call, tokens tab-separated, then a stream
# just long enough for the scorer to read a model out of it.
line="$(printf '%s\t' "$@" | tr '\n' ' ')"
printf '%s\n' "$line" >> "$STUB_LOG"
printf '{"type":"system","subtype":"init","model":"claude-haiku-4-5-20251001","tools":["Bash","Read","Skill"]}\n'
printf '{"type":"result","result":"ok","permission_denials":[]}\n'
STUB
chmod +x "$STUB/claude"
( cd "$PACK" && HOME="$H" PATH="$STUB:$PATH" N_RUNS=1 EVAL_MODEL=haiku EVAL_PARALLEL=1 \
    bash evals/run.sh > "$STUB/run.out" 2>&1 )
check "the runner finishes" 0 $?
T=$'\t'
runs="$(grep -c -- "stream-json" "$STUB_LOG")"
files="$(find "$H/.claude/open-steps/evals" -name '*.jsonl' | wc -l | tr -d ' ')"
check "one stream per run ($runs runs)" "$runs" "$files"
check "every run carries the deny list" "$runs" \
  "$(grep -c -- "--disallowedTools${T}SendMessage${T}ListAgents${T}" "$STUB_LOG")"
qual="$(grep -- "Say this again in plain words" "$STUB_LOG")"
check "two quality runs" 2 "$(printf '%s\n' "$qual" | grep -c .)"
check "both quality runs may load a skill" 2 \
  "$(printf '%s\n' "$qual" | grep -c -- "--allowedTools${T}Skill${T}")"
check "the arms differ by the skills switch alone" 1 \
  "$(printf '%s\n' "$qual" | sed "s/--disable-slash-commands${T}//" | sort -u | grep -c .)"
check "the activation arm is left as it was" 0 \
  "$(grep -v -- "Say this again in plain words" "$STUB_LOG" | grep -c -- "--allowedTools")"
rm -rf "$H" "$STUB"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
