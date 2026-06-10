#!/bin/bash
# QuickPDF.files.selection.changed.sh - Handle file selection changes

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

# Column 1 is filename, column 2 is the full path (hidden)
selected_path="$OMC_ACTIONUI_TABLE_10_COLUMN_2_VALUE"

if [ -n "$selected_path" ]; then
    "$dialog_tool" "$window_uuid" ${REMOVE_BUTTON_ID} omc_enable
    "$dialog_tool" "$window_uuid" ${REVEAL_BUTTON_ID} omc_enable
    "$dialog_tool" "$window_uuid" ${PREVIEW_BUTTON_ID} omc_enable
    "$dialog_tool" "$window_uuid" ${INFO_BUTTON_ID} omc_enable

    if [ -e "$selected_path" ]; then
        size="$(/usr/bin/stat -f %z "$selected_path" 2>/dev/null)"
        pages="$("$QPDF" --show-npages "$selected_path" 2>/dev/null)"
        encrypted="No"
        if "$QPDF" --is-encrypted "$selected_path" 2>/dev/null; then
            encrypted="Yes"
        fi
        set_summary "$(/usr/bin/basename "$selected_path")
Size: $(format_size "$size")
Pages: ${pages:-?}
Encrypted: $encrypted"
    fi
else
    "$dialog_tool" "$window_uuid" ${REMOVE_BUTTON_ID} omc_disable
    "$dialog_tool" "$window_uuid" ${REVEAL_BUTTON_ID} omc_disable
    "$dialog_tool" "$window_uuid" ${PREVIEW_BUTTON_ID} omc_disable
    "$dialog_tool" "$window_uuid" ${INFO_BUTTON_ID} omc_disable
fi
