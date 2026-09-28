#!/bin/bash
# Run strategies concurrently and pipe their results into refinement.
set -euo pipefail
BOOK_ROOT=$(cd "$(dirname "$0")/.." && pwd)
: "${BOOK_DB:=$BOOK_ROOT/data/books.csv}"
export BOOK_ROOT BOOK_DB
work=$(mktemp -d)
pids=()
names=(history interests discovery)
scripts=(recommend_from_history recommend_from_interests recommend_for_discovery)
cleanup() {
    local pid
    # Bash 3.2 treats an empty array as unbound under set -u.
    if [ "${#pids[@]}" -gt 0 ]; then
        for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
        for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
    fi
    rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Generate a temporary output schema.
jq -n '{type:"object", properties:{books:{type:"array", minItems:1, maxItems:3,
    items:{type:"object", properties:(["title","author","genre","reason"] |
    map({key:.,value:{type:"string"}}) | from_entries),
    required:["title","author","genre","reason"], additionalProperties:false}}},
    required:["books"], additionalProperties:false}' > "$work/schema.json"
# Python supplies portable process groups (macOS has no built-in timeout command).
# Each background function becomes its supervisor, so $! is the process we cancel.
run_strategy() {
    exec python3 - "${BOOK_AI_TIMEOUT:-120}" "$work/library" \
        bash "$BOOK_ROOT/recommendations/$1.sh" "${2-}" "$work/schema.json" <<'PYTHON'
import os
import signal
import subprocess
import sys

seconds = float(sys.argv[1])
if seconds <= 0:
    sys.exit('Timeout must be positive.')
with open(sys.argv[2]) as library:
    child = subprocess.Popen(sys.argv[3:], stdin=library, start_new_session=True)

def stop_group():
    try:
        os.killpg(child.pid, signal.SIGTERM)
        child.wait(timeout=1)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        pass
    finally:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        child.wait()

def interrupted(signum, _frame):
    stop_group()
    sys.exit(128 + signum)

signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
try:
    result = child.wait(timeout=seconds)
except subprocess.TimeoutExpired:
    print('AI request timed out. Try again later.', file=sys.stderr)
    result = 124
finally:
    stop_group()
sys.exit(result if result >= 0 else 128 - result)
PYTHON
}
bash "$BOOK_ROOT/data/book_database.sh" list > "$work/library"
for i in 0 1 2; do
    run_strategy "${scripts[$i]}" "${1-}" > "$work/${names[$i]}.out" 2> "$work/${names[$i]}.err" &
    pids[i]=$!
done
states=(running running running)
start=$SECONDS
previous=
while :; do
    active=0
    for i in 0 1 2; do
        if [ "${states[$i]}" = running ]; then
            if kill -0 "${pids[$i]}" 2>/dev/null; then
                active=$((active + 1))
            elif wait "${pids[$i]}"; then
                states[i]='done'
            else
                status=$?
                printf '%s failed (exit %s). Check connectivity or Codex allowance.\n' "${names[$i]}" "$status" >&2
                states[i]=failed
                cat "$work/${names[$i]}.err" >&2
                : > "$work/${names[$i]}.out"
            fi
        fi
    done
    message="History: ${states[0]} | Interests: ${states[1]} | Discovery: ${states[2]}"
    if [ "$message" != "$previous" ] || [ $(((SECONDS - start) % 5)) -eq 0 ]; then
        printf '[%ss] %s\n' "$((SECONDS - start))" "$message" >&2
        previous=$message
    fi
    [ "$active" -gt 0 ] || break
    sleep 1
done
pids=()
if [ "${states[*]}" = 'failed failed failed' ]; then
    echo 'No recommendations available. Library features still work.' >&2
    exit 1
fi
cat "$work/history.out" "$work/interests.out" "$work/discovery.out" |
    bash "$BOOK_ROOT/recommendations/refine_recommendations.sh"
