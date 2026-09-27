#!/bin/bash
# stdin: candidate JSONL; stdout: up to five balanced recommendations.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
# Read the library only through its public interface.
owned=$(bash "$BOOK_ROOT/data/book_database.sh" list | jq -s '.')
exec 3<&0
python3 - "$owned" <<'PY'
import json
import os
import sys
import unicodedata

def key(book):
    return tuple(' '.join(unicodedata.normalize('NFKC', book[k]).casefold().split())
                 for k in ('title', 'author'))

seen = {key(book) for book in json.loads(sys.argv[1])}
groups = {name: [] for name in ('history', 'interests', 'discovery')}
with os.fdopen(3) as stream:
    for line in stream:
        try:
            book = json.loads(line)
            if not isinstance(book, dict):
                raise ValueError()
            for field in ('title', 'author', 'genre', 'reason'):
                if not isinstance(book.get(field), str) or not book[field].strip():
                    raise ValueError()
                if any(ord(c) < 32 or ord(c) == 127 for c in book[field]):
                    raise ValueError()
            groups[book['strategy']].append(book)
        except (ValueError, KeyError, TypeError):
            print('Skipped malformed recommendation.', file=sys.stderr)
count = 0
while any(groups.values()) and count < 5:
    for books in groups.values():
        while books:
            book = books.pop(0)
            identity = key(book)
            if identity in seen:
                continue
            seen.add(identity)
            print(json.dumps(book, ensure_ascii=False))
            count += 1
            break
        if count == 5:
            break
PY
