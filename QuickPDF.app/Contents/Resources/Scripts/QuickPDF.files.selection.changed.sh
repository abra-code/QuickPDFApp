#!/bin/bash
# QuickPDF.files.selection.changed.sh - Handle file selection changes

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

# Column 1 is filename, column 2 is the full path (hidden). This handler fires
# on a real user selection, so the live table value is current here.
apply_file_selection "$OMC_ACTIONUI_TABLE_10_COLUMN_2_VALUE"
