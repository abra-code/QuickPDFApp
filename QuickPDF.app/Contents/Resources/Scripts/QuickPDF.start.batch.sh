#!/bin/bash
# QuickPDF.start.batch.sh - Run button: validate, then route to the right runner
#
# Inspect is read-only and needs no destination -> chain to QuickPDF.inspect.run
# (output window). Everything else writes files -> chain to QuickPDF.run.batch,
# whose CHOOSE_FOLDER_DIALOG asks for the destination folder.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

file_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_2_ALL_ROWS"

if [ -z "$file_paths" ]; then
    "$alert_tool" --level caution --title "QuickPDF" "Add some PDF files to the list first."
    exit 0
fi

operation="$OMC_ACTIONUI_VIEW_60_VALUE"
[ -z "$operation" ] && operation="optimize"

case "$operation" in
    inspect)
        "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "QuickPDF.inspect.run"
        ;;
    encrypt)
        user_pw="$OMC_ACTIONUI_VIEW_110_VALUE"
        owner_pw="$OMC_ACTIONUI_VIEW_111_VALUE"
        if [ -z "$user_pw" ] && [ -z "$owner_pw" ]; then
            "$alert_tool" --level caution --title "QuickPDF" \
                "Enter a user password (and optionally an owner password) before encrypting."
            exit 0
        fi
        "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "QuickPDF.run.batch"
        ;;
    *)
        "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "QuickPDF.run.batch"
        ;;
esac
