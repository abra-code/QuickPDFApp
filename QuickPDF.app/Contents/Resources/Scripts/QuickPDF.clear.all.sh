#!/bin/bash
# QuickPDF.clear.all.sh - Clear all files from table

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

"$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_remove_all_rows

"$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "QuickPDF.files.selection.changed"
