#!/bin/bash
# Accept a positional search term or a line from stdin.
set -eu
BOOK_ROOT=$(cd "$(dirname "$0")/.." && pwd)
: "${BOOK_DB:=$BOOK_ROOT/data/books.csv}"
export BOOK_ROOT BOOK_DB
term=${1-}
if [ "$#" -eq 0 ]; then IFS= read -r term || true; fi
exec bash "$BOOK_ROOT/data/book_database.sh" search "$term"
