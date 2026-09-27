#!/bin/bash
# Three background processes, progress on stderr, a real refinement pipeline.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
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
bash "$BOOK_ROOT/data/book_database.sh" list > "$work/library"
for i in 0 1 2; do
    bash "$BOOK_ROOT/recommendations/${scripts[$i]}.sh" "${1-}" \
        < "$work/library" > "$work/${names[$i]}.out" 2> "$work/${names[$i]}.err" &
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
