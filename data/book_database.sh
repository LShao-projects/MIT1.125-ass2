#!/bin/bash
# Only this component opens library CSV files. JSON Lines are the public interface.
set -eu
# shellcheck source=lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
# Preserve stdin for JSON input; Python's source is supplied separately.
exec 3<&0
python3 - "$BOOK_DB" "$@" <<'PY'
import csv
import json
import os
import sys
import tempfile
import unicodedata

FIELDS = ['title', 'author', 'genre', 'status', 'rating', 'link']
STATUSES = ['want-to-read', 'reading', 'finished']

def normalize(value):
    return ' '.join(unicodedata.normalize('NFKC', value).casefold().split())

def identity(book):
    return normalize(book['title']), normalize(book['author'])

def validate(book):
    if not isinstance(book, dict) or set(book) - set(FIELDS):
        raise ValueError('Expected a book object with the documented fields.')
    row = {k: book.get(k, '') for k in FIELDS}
    for k, value in row.items():
        if not isinstance(value, str):
            raise ValueError(k + ' must be a string.')
        row[k] = value.strip()
        if any(ord(c) < 32 or ord(c) == 127 for c in row[k]):
            raise ValueError(k + ' cannot contain control characters.')
    if not row['title'] or not row['author']:
        raise ValueError('Title and author are required.')
    if row['status'] not in STATUSES:
        raise ValueError('Status must be want-to-read, reading, or finished.')
    if row['rating'] not in ['', '1', '2', '3', '4', '5']:
        raise ValueError('Rating must be blank or 1–5.')
    if row['link'] and not row['link'].startswith(('https://', 'http://')):
        raise ValueError('Link must be an http(s) URL or blank.')
    return row

def emit(row):
    print(json.dumps(row, ensure_ascii=False))

def save(path, rows):
    path = os.path.abspath(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix='.books-', dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=FIELDS)
            writer.writeheader()
            writer.writerows(rows)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)

try:
    path, args = sys.argv[1], sys.argv[2:]
    if not args:
        raise ValueError('Usage: book_database.sh add|list|search TERM|update TITLE AUTHOR|exists TITLE AUTHOR')
    command, params = args[0], args[1:]
    counts = {'add': 0, 'list': 0, 'search': 1, 'update': 2, 'exists': 2}
    if command not in counts or len(params) != counts[command]:
        raise ValueError('Invalid command or argument count.')
    rows = []
    if os.path.exists(path):
        with open(path, newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames != FIELDS:
                raise ValueError('Unexpected CSV header; library left unchanged.')
            rows = [validate(row) for row in reader]
    if command == 'list':
        for row in rows:
            emit(row)
    elif command == 'search':
        term = normalize(params[0])
        for row in rows:
            if any(term in normalize(row[k]) for k in ['title', 'author', 'genre']):
                emit(row)
    elif command == 'exists':
        target = tuple(map(normalize, params))
        sys.exit(0 if any(identity(row) == target for row in rows) else 1)
    else:
        with os.fdopen(3) as source:
            incoming = json.load(source)
        if command == 'add':
            if isinstance(incoming, dict):
                incoming.setdefault('status', 'want-to-read')
            row = validate(incoming)
            if any(identity(other) == identity(row) for other in rows):
                raise ValueError('This book is already in your library.')
            rows.append(row)
        else:
            if not isinstance(incoming, dict) or not incoming or set(incoming) - {'status', 'rating'}:
                raise ValueError('Updates accept status and/or rating only.')
            index = next((i for i, r in enumerate(rows) if identity(r) == tuple(map(normalize, params))), None)
            if index is None:
                raise ValueError('Book not found.')
            row = validate(dict(rows[index], **incoming))
            rows[index] = row
        save(path, rows)
        emit(row)
except (ValueError, OSError, csv.Error) as error:
    print('Library: ' + str(error), file=sys.stderr)
    sys.exit(2)
PY
