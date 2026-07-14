#!/bin/bash
# QuickPDF.quicklook.sh - preview the selected file in a native Quick Look window.
# Runs in the main window context, so it reads the live table selection, hands the
# path to the Quick Look window's init via the private pasteboard, then opens the
# window (its ACTIONUI_WINDOW runs QuickPDF.quicklook.init).

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

QL_PB_KEY="QUICKPDF_QUICKLOOK_PATH"

# Column 1 is filename, column 2 is the full path (hidden)
selected_path="$OMC_ACTIONUI_TABLE_10_COLUMN_2_VALUE"

if [ -n "$selected_path" ] && [ -e "$selected_path" ]; then
    "$pasteboard_tool" "$QL_PB_KEY" put "$selected_path"
    "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "QuickPDF.quicklook.window"
else
    "$alert_tool" --level caution --title "QuickPDF" "File does not exist"
fi
