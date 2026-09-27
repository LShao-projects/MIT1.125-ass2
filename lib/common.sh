#!/bin/bash
# Shared paths only: this file does not start the UI or read the library.
BOOK_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export BOOK_ROOT
: "${BOOK_DB:=$BOOK_ROOT/data/books.csv}"
export BOOK_DB
