#!/bin/bash
# Return up to five Open Library matches as JSON Lines. Never saves books.
set -euo pipefail
query=${1:?Usage: fetch_book_metadata.sh TITLE [AUTHOR]}
author=${2-}
response=$(curl --fail --silent --show-error --get --max-time 15 \
    --user-agent 'FantasyBookManager/1.0 (student terminal project)' \
    --data-urlencode "title=$query" --data-urlencode "author=$author" \
    --data-urlencode 'fields=title,author_name,key,subject' --data-urlencode 'limit=5' \
    'https://openlibrary.org/search.json') || {
    echo 'Book lookup unavailable. You can enter details manually.' >&2; exit 1;
}
printf '%s\n' "$response" | jq -ce '
    if (.docs | type) != "array" then error("Invalid search response") else
    .docs[:5][] | select((.title | type) == "string") |
    {title: .title, author: ((.author_name // [])[0] // ""),
     genre: (if any(.subject[]?; test("fantasy"; "i")) then "Fantasy" else "" end),
     status: "want-to-read", rating: "",
     link: (if (.key // "" | test("^/works/[A-Za-z0-9]+$")) then "https://openlibrary.org" + .key
            elif (.key // "" | test("^OL[0-9]+W$")) then "https://openlibrary.org/works/" + .key
            else "" end)} end' || {
    # jq -e returns 4 for an empty result set, which is a normal no-match outcome.
    if printf '%s\n' "$response" | jq -e '.docs == []' >/dev/null; then exit 0; fi
    echo 'Could not interpret book metadata. Manual entry is available.' >&2; exit 1;
}
