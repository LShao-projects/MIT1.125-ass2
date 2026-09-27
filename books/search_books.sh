#!/bin/bash
# Accept a positional search term or a line from stdin.
set -eu
# shellcheck source=lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
term=${1-}
if [ "$#" -eq 0 ]; then IFS= read -r term || true; fi
exec bash "$BOOK_ROOT/data/book_database.sh" search "$term"
