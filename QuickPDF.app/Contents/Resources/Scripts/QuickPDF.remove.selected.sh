#!/bin/bash
# QuickPDF.remove.selected.sh - Remove selected file from table

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

selected_path="$OMC_ACTIONUI_TABLE_10_COLUMN_2_VALUE"

if [ -n "$selected_path" ]; then
    all_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_2_ALL_ROWS"

    buffer=""
    while IFS= read -r file_path; do
        if [ -n "$file_path" ] && [ "$file_path" != "$selected_path" ]; then
            filename="$(/usr/bin/basename "$file_path")"
            buffer="${buffer}${filename}	${file_path}
"
        fi
    done <<< "$all_paths"

    # Not sorted: the rest of the list keeps the order the user gave it.
    printf "%s" "$buffer" | "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_set_rows_from_stdin
fi

"$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "QuickPDF.files.selection.changed"
