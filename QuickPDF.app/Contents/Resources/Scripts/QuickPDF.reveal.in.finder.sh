#!/bin/bash
# QuickPDF.reveal.in.finder.sh - Reveal selected file in Finder

selected_path="$OMC_ACTIONUI_TABLE_10_COLUMN_2_VALUE"

if [ -n "$selected_path" ] && [ -e "$selected_path" ]; then
    /usr/bin/open -R "$selected_path"
else
    "$OMC_OMC_SUPPORT_PATH/alert" --level caution --title "QuickPDF" "File does not exist"
fi
