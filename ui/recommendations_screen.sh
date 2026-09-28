#!/bin/bash
# Session cache lives in the menu process, never in the CSV or on disk.
RECOMMENDATIONS=
recommendations_screen() {
    local action interest results book choice
    section_banner 'The reading oracle'
    gum style --foreground 60 --italic '  History · Interests · Discovery'
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
                gum style --foreground 94 --margin '1 0' '  ✧  Generating recommendations… (Ctrl-C cancels)'
                if results=$(bash "$BOOK_ROOT/workflows/get_recommendations.sh" "$interest"); then
                    RECOMMENDATIONS=$results
                    if [ -z "$results" ]; then gum style --foreground 60 'No new recommendations found.'; pause_screen; continue; fi
                else
                    gum style --foreground 94 --width "$(card_width)" 'Recommendations unavailable. You can still manage your library.'
                    pause_screen
                    continue
                fi ;;
        esac
        book=$(select_book "$RECOMMENDATIONS" 'Choose a recommendation (Esc to return)') || continue
        show_book "$book"
        choice=$(gum choose --header 'Next step' 'Review and save' Back) || continue
        [ "$choice" = 'Review and save' ] || continue
        # Keep the selected recommendation; edits are made only by the user.
        book=$(jq -c '. + {status:"want-to-read",rating:""}' <<< "$book")
        review_and_save "$book"
    done
}
