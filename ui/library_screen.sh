#!/bin/bash
# UI functions: select, display, and edit records. No storage access here.
select_book() {
    local records=$1 heading=${2:-Choose a book (Esc to return)} selection index
    if [ -z "$records" ]; then echo 'No books found.' >&2; return 1; fi
    selection=$(printf '%s\n' "$records" | jq -sr '
        to_entries[] | "\(.key + 1). \(.value.title) — \(.value.author)"' |
        gum choose --header "$heading") || return 1
    index=${selection%%.*}
    printf '%s\n' "$records" | jq -sc --argjson index "$index" '.[$index - 1]'
}
show_book() {
    printf '%s\n' "$1" | jq -r '
        "\n\(.title)\nby \(.author)\nGenre: \(.genre // "")\nStatus: \(.status // "not saved")\nRating: \(if (.rating // "") == "" then "unrated" else .rating + "/5" end)\nLink: \(.link // "")",
        (if .reason then "Why: " + .reason + "\nStrategy: " + .strategy else empty end)'
}
pause_screen() {
    gum choose --header 'Press Enter to return' Back >/dev/null || true
}
edit_book() {
    local book=$1 title author genre link progress
    title=$(gum input --header 'Title (required)' --value "$(jq -r '.title // ""' <<< "$book")") || return 1
    author=$(gum input --header 'Author (required)' --value "$(jq -r '.author // ""' <<< "$book")") || return 1
    genre=$(gum input --header 'Genre (optional)' --value "$(jq -r '.genre // ""' <<< "$book")") || return 1
    link=$(gum input --header 'Book information URL (optional)' --value "$(jq -r '.link // ""' <<< "$book")") || return 1
    progress=$(choose_update "$book") || return 1
    jq -nc --arg title "$title" --arg author "$author" --arg genre "$genre" \
        --arg link "$link" --argjson progress "$progress" \
        '{title:$title,author:$author,genre:$genre,link:$link} + $progress'
}
choose_update() {
    local book=$1 status rating
    status=$(gum choose --header 'Reading status' --selected "$(jq -r '.status // "want-to-read"' <<< "$book")" \
        want-to-read reading finished) || return 1
    rating=$(gum choose --header 'Rating' --selected "$(jq -r 'if (.rating // "") == "" then "unrated" else .rating end' <<< "$book")" \
        unrated 1 2 3 4 5) || return 1
    [ "$rating" != unrated ] || rating=
    jq -nc --arg status "$status" --arg rating "$rating" '{status:$status,rating:$rating}'
}

request_new_book() {
    local title author method
    title=$(gum input --header 'Book title') || return 1
    [ -n "$title" ] || return 1
    author=$(gum input --header 'Author (optional for lookup)') || return 1
    method=$(gum choose --header 'How would you like to add it?' 'Look up details' 'Enter manually' Back) || return 1
    [ "$method" != Back ] || return 1
    jq -nc --arg title "$title" --arg author "$author" --arg method "$method" \
        '{book:{title:$title,author:$author},method:$method}'
}
select_metadata() {
    local matches=$1 original=$2 method
    if [ -n "$matches" ]; then
        method=$(gum choose --header 'Metadata found' 'Choose a match' 'Enter manually' Back) || return 1
        case "$method" in
            Back) return 1 ;;
            'Choose a match') select_book "$matches"; return $? ;;
        esac
    else
        gum confirm 'No usable metadata. Enter details manually?' || return 1
    fi
    printf '%s\n' "$original"
}
review_book() {
    local edited
    edited=$(edit_book "$1") || return 1
    # stdout carries the confirmed record; the preview stays on the terminal.
    show_book "$edited" >&2
    gum confirm 'Save this book?' || return 1
    printf '%s\n' "$edited"
}
request_search() {
    gum input --header 'Search title, author, or genre'
}
