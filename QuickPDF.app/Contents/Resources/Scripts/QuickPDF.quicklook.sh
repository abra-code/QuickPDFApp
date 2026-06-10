#!/bin/bash
# QuickPDF.quicklook.sh - QuickLook preview of the selected file

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

# Column 1 is filename, column 2 is the full path (hidden)
selected_path="$OMC_ACTIONUI_TABLE_10_COLUMN_2_VALUE"

if [ -n "$selected_path" ] && [ -e "$selected_path" ]; then
    /usr/bin/qlmanage -p "$selected_path" >/dev/null 2>&1
else
    "$alert_tool" --level caution --title "QuickPDF" "File does not exist"
fi
