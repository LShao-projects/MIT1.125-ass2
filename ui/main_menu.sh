#!/bin/bash
source "$BOOK_ROOT/workflows/manage_library.sh"
source "$BOOK_ROOT/ui/recommendations_screen.sh"
main_menu() {
    local action
    gum style --foreground 212 --border rounded --padding '1 3' 'THE FANTASY SHELF' 'A home for books and new adventures'
    if [ "${BOOK_DEMO:-0}" = 1 ]; then
        echo 'DEMO: temporary sample library. AI recommendations are live and use your allowance.'
    fi
    while action=$(gum choose --header 'Where next? (Esc to quit)' \
        'Browse Library' 'Add Book' 'Search Library' 'Update Status / Rating' 'Get Recommendations' Quit); do
        case "$action" in
            'Browse Library') browse_library ;;
            'Add Book') add_book ;;
            'Search Library') search_library ;;
            'Update Status / Rating') update_book ;;
            'Get Recommendations') recommendations_screen ;;
            Quit) break ;;
        esac
    done
    echo 'Until the next chapter.'
}
