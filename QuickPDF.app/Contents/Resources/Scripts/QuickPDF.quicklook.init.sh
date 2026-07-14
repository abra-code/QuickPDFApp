#!/bin/bash
# QuickPDF.quicklook.init.sh - populate the Quick Look window. Runs in the new
# window's context; reads the file path handed off via the private pasteboard,
# points the QuickLook view (id 200) at it, and titles the window.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

QL_VIEW_ID=200
QL_PB_KEY="QUICKPDF_QUICKLOOK_PATH"

selected_path="$("$pasteboard_tool" "$QL_PB_KEY" get)"
"$pasteboard_tool" "$QL_PB_KEY" set ""

if [ -n "$selected_path" ] && [ -e "$selected_path" ]; then
    "$dialog_tool" "$window_uuid" ${QL_VIEW_ID} "$selected_path"
    "$dialog_tool" "$window_uuid" omc_window "Quick Look - $(/usr/bin/basename "$selected_path")"
fi
