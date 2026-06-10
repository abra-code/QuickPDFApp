#!/bin/bash
# QuickPDF.init.sh - Initialize the window

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

# Start with an empty file list
"$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_remove_all_rows

qpdf_version="$("$QPDF" --version 2>/dev/null | /usr/bin/head -1)"
set_summary "Drop PDF files into the list, pick an operation, then press Run.

Engine: ${qpdf_version:-qpdf (missing!)}"

# Seed the file list: from objects dropped on the app icon, or from the
# Open… panel selection handed off via the private pasteboard
if [ -n "$OMC_OBJ_PATH" ]; then
    add_files_to_table "$OMC_OBJ_PATH"
else
    open_paths="$("$pasteboard_tool" "$OPEN_PATHS_PB_KEY" get)"
    if [ -n "$open_paths" ]; then
        "$pasteboard_tool" "$OPEN_PATHS_PB_KEY" set ""
        add_files_to_table "$open_paths"
    fi
fi
