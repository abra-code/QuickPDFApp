#!/bin/bash
# QuickPDF.add.files.sh - Add files via file picker

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

# Files selected via CHOOSE_OBJECT_DIALOG arrive in OMC_DLG_CHOOSE_OBJECT_PATH
if [ -n "$OMC_DLG_CHOOSE_OBJECT_PATH" ]; then
    add_files_to_table "$OMC_DLG_CHOOSE_OBJECT_PATH"
fi

"$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "QuickPDF.files.selection.changed"
