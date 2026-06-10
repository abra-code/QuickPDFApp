#!/bin/bash
# QuickPDF.files.double.click.sh - Open double-clicked file in default viewer

selected_path="$OMC_ACTIONUI_TABLE_10_COLUMN_2_VALUE"

if [ -n "$selected_path" ] && [ -e "$selected_path" ]; then
    /usr/bin/open "$selected_path"
fi
