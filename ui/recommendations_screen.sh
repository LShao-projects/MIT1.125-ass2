#!/bin/bash
# Session cache lives in the menu process, never in the CSV or on disk.
RECOMMENDATIONS=
recommendations_screen() {
    local action interest results book matches choice
    while :; do
        if [ -n "$RECOMMENDATIONS" ]; then
            action=$(gum choose --header 'Your recommendations' 'Browse last results' 'Generate new recommendations' Back) || return 0
        else
            action=$(gum choose --header 'AI recommendations use your Codex allowance' 'Generate new recommendations' Back) || return 0
        fi
        case "$action" in
            Back) return 0 ;;
            'Generate new recommendations')
                interest=$(gum input --header 'Any interests today? (optional)' --placeholder 'e.g. dragons, cozy magic, epic journeys') || continue
                echo 'Three readers are finding your next adventure… (Ctrl-C cancels)'
                if results=$(bash "$BOOK_ROOT/workflows/get_recommendations.sh" "$interest"); then
                    RECOMMENDATIONS=$results
                    if [ -z "$results" ]; then echo 'No new books survived refinement.'; pause_screen; continue; fi
                else
                    echo 'Recommendations unavailable. You can still manage your library.'
                    pause_screen
                    continue
                fi ;;
        esac
        book=$(select_book "$RECOMMENDATIONS") || continue
        show_book "$book"
        choice=$(gum choose --header 'Next step' 'Save to library' Back) || continue
        [ "$choice" = 'Save to library' ] || continue
        # Metadata is reviewed before saving; never trust an AI-invented URL.
        if matches=$(bash "$BOOK_ROOT/books/fetch_book_metadata.sh" "$(jq -r .title <<< "$book")" "$(jq -r .author <<< "$book")") && [ -n "$matches" ]; then
            choice=$(gum choose --header 'Review metadata' 'Choose a match' 'Use recommendation details' Back) || continue
            case "$choice" in
                Back) continue ;;
                'Choose a match') book=$(select_book "$matches") || continue ;;
            esac
        fi
        book=$(jq -c '. + {status:"want-to-read",rating:""}' <<< "$book")
        review_and_save "$book"
    done
}
