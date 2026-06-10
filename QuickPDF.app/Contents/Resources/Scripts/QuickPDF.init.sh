#!/bin/bash
# QuickPDF.init.sh - Initialize the window

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

# Start with an empty file list
"$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_remove_all_rows

qpdf_version="$("$QPDF" --version 2>/dev/null | /usr/bin/head -1)"
set_summary "Drop PDF files into the list, pick an operation, then press Run.

Engine: ${qpdf_version:-qpdf (missing!)}"

# If files were dropped on the app icon, add them
if [ -n "$OMC_OBJ_PATH" ]; then
    add_files_to_table "$OMC_OBJ_PATH"
fi
