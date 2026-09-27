#!/bin/bash
# Functions called by the menu: coordinate components and UI.
source "$BOOK_ROOT/ui/library_screen.sh"
review_and_save() {
    local book=$1 edited saved
    edited=$(edit_book "$book") || return 0
    show_book "$edited"
    gum confirm 'Save this book?' || return 0
    if saved=$(printf '%s\n' "$edited" | bash "$BOOK_ROOT/data/book_database.sh" add); then
        printf 'Saved: %s\n' "$(jq -r .title <<< "$saved")"
    fi
    pause_screen
}
add_book() {
    local title author matches book method
    title=$(gum input --header 'Book title') || return 0
    [ -n "$title" ] || return 0
    author=$(gum input --header 'Author (optional for lookup)') || return 0
    book=$(jq -nc --arg title "$title" --arg author "$author" '{title:$title,author:$author}')
    method=$(gum choose --header 'How would you like to add it?' 'Look up details' 'Enter manually' Back) || return 0
    case "$method" in
        Back) return 0 ;;
        'Look up details')
            echo 'Looking up book details…'
            if matches=$(bash "$BOOK_ROOT/books/fetch_book_metadata.sh" "$title" "$author") && [ -n "$matches" ]; then
                method=$(gum choose --header 'Metadata found' 'Choose a match' 'Enter manually' Back) || return 0
                case "$method" in
                    Back) return 0 ;;
                    'Choose a match') book=$(select_book "$matches") || return 0 ;;
                esac
            else
                gum confirm 'No usable metadata. Enter details manually?' || return 0
            fi ;;
    esac
    review_and_save "$book"
}
browse_library() {
    local records book
    records=$(bash "$BOOK_ROOT/data/book_database.sh" list) || { pause_screen; return; }
    if book=$(select_book "$records"); then show_book "$book"; fi
    pause_screen
}
search_library() {
    local term records book
    term=$(gum input --header 'Search title, author, or genre') || return 0
    records=$(bash "$BOOK_ROOT/books/search_books.sh" "$term") || { pause_screen; return; }
    if book=$(select_book "$records"); then show_book "$book"; fi
    pause_screen
}
update_book() {
    local records book patch title author
    records=$(bash "$BOOK_ROOT/data/book_database.sh" list) || { pause_screen; return; }
    book=$(select_book "$records") || { pause_screen; return; }
    patch=$(choose_update "$book") || return 0
    title=$(jq -r .title <<< "$book")
    author=$(jq -r .author <<< "$book")
    if printf '%s\n' "$patch" | bash "$BOOK_ROOT/data/book_database.sh" update "$title" "$author" >/dev/null; then
        echo 'Reading progress updated.'
    fi
    pause_screen
}
