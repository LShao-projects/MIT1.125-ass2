#!/bin/bash
# Entry point: dependencies, optional isolated demo library, then the UI.
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"
case "${1-}" in
    --help|-h) echo 'Usage: bash app.sh [--demo]'; exit 0 ;;
    ''|--demo) ;;
    *) echo 'Usage: bash app.sh [--demo]' >&2; exit 2 ;;
esac
for dependency in gum jq python3 curl; do
    command -v "$dependency" >/dev/null || {
        echo "Missing $dependency. See README setup instructions (macOS: brew install gum jq python)." >&2
        exit 1
    }
done
if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo 'Run this menu in an interactive terminal. Component scripts support pipes.' >&2
    exit 1
fi
demo_dir=
cleanup() { [ -z "$demo_dir" ] || rm -rf "$demo_dir"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [ "${1-}" = --demo ]; then
    demo_dir=$(mktemp -d) || exit 1
    export BOOK_DB="$demo_dir/books.csv" BOOK_DEMO=1
    while IFS= read -r book; do
        printf '%s\n' "$book" | bash "$BOOK_ROOT/data/book_database.sh" add >/dev/null || exit 1
    done <<'BOOKS'
{"title":"The Fellowship of the Ring","author":"J. R. R. Tolkien","genre":"Epic Fantasy","status":"finished","rating":"5","link":""}
{"title":"A Wizard of Earthsea","author":"Ursula K. Le Guin","genre":"Fantasy","status":"reading","rating":"","link":""}
{"title":"The Last Unicorn","author":"Peter S. Beagle","genre":"Fantasy","status":"want-to-read","rating":"","link":""}
BOOKS
fi
source "$BOOK_ROOT/ui/main_menu.sh"
main_menu
