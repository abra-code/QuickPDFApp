#!/bin/bash
# QuickPDF.info.sh - Show detailed PDF info in an output window

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

selected_path="$OMC_ACTIONUI_TABLE_10_COLUMN_2_VALUE"

if [ -z "$selected_path" ]; then
    echo "No file selected"
    exit 0
fi

if [ ! -e "$selected_path" ]; then
    echo "File does not exist: $selected_path"
    exit 0
fi

file_size="$(/usr/bin/stat -f %z "$selected_path" 2>/dev/null)"
created="$(/usr/bin/stat -f "%SB" "$selected_path" 2>/dev/null)"
modified="$(/usr/bin/stat -f "%Sm" "$selected_path" 2>/dev/null)"

echo "File: $selected_path"
echo ""
echo "Size: $(format_size "$file_size") ($file_size bytes)"
echo "Created: $created"
echo "Modified: $modified"
echo ""

pages="$("$QPDF" --show-npages "$selected_path" 2>&1)"
echo "Pages: $pages"
echo ""

echo "--- Encryption ---"
"$QPDF" --show-encryption "$selected_path" 2>&1
echo ""

echo "--- Structure check ---"
"$QPDF" --check "$selected_path" 2>&1
