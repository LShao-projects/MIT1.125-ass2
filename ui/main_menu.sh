#!/bin/bash
source "$BOOK_ROOT/workflows/manage_library.sh"
source "$BOOK_ROOT/ui/recommendations_screen.sh"
main_menu() {
    local action
    fantasy_theme
    shelf_banner
    if [ "${BOOK_DEMO:-0}" = 1 ]; then
        gum style --foreground 241 --padding '0 2' --width "$(card_width)" \
            'DEMO: temporary sample library. AI recommendations are live and use your allowance.'
    fi
    while action=$(gum choose --header 'Where next? (Esc to quit)' \
        'Browse Library' 'Add Book' 'Search Library' 'Update Status / Rating' 'Get Recommendations' Quit); do
        case "$action" in
            'Browse Library') section_banner 'Your collection'; browse_library ;;
            'Add Book') add_book ;;
            'Search Library') search_library ;;
            'Update Status / Rating') section_banner 'Chronicle your reading'; update_book ;;
            'Get Recommendations') recommendations_screen ;;
            Quit) break ;;
        esac
    done
    gum style --foreground 94 --italic --margin '1 0' '  ✦  Until the next chapter.'
}
