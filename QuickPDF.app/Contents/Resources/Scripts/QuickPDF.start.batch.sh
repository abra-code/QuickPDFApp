#!/bin/bash
# QuickPDF.start.batch.sh - Run button: validate, then route to the right runner
#
# Routing logic:
# - inspect: output window, no save dialog
# - merge: always N:1 → SAVE_AS_DIALOG (QuickPDF.run.merge)
# - 1 file + 1:1 operation (optimize, encrypt, decrypt, rotate, repair, metadata, flatten):
#   → SAVE_AS_DIALOG (QuickPDF.run.single) — single-document "Save As" panel
# - split / extract (even with 1 file): always produce N outputs → CHOOSE_FOLDER_DIALOG
# - all other multi-file cases: CHOOSE_FOLDER_DIALOG via QuickPDF.run.batch
#
# Different dialog types (file vs folder) are achieved by chaining with
# omc_next_command to a command that declares the appropriate *_DIALOG.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

# env | sort

file_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_2_ALL_ROWS"

if [ -z "$file_paths" ]; then
    "$alert_tool" --level caution --title "QuickPDF" "Add some PDF files to the list first."
    exit 0
fi

operation="$OMC_ACTIONUI_VIEW_60_VALUE"
[ -z "$operation" ] && operation="optimize"

# Count files early. We use this to decide between single-document "Save As"
# panel (most 1:1 operations with exactly one input) vs. batch folder selection.
file_count=$(printf '%s\n' "$file_paths" | /usr/bin/grep -c .)

case "$operation" in
    inspect)
        "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "QuickPDF.inspect.run"
        ;;
    encrypt)
        user_pw="$OMC_ACTIONUI_VIEW_110_VALUE"
        owner_pw="$OMC_ACTIONUI_VIEW_111_VALUE"
        if [ -z "$user_pw" ] && [ -z "$owner_pw" ]; then
            "$alert_tool" --level caution --title "QuickPDF" \
                "Enter a user password (and optionally an owner password) before encrypting."
            exit 0
        fi
        if [ "$file_count" -eq 1 ]; then
            "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "QuickPDF.run.single"
        else
            "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "QuickPDF.run.batch"
        fi
        ;;
    extract)
        if [ -z "$OMC_ACTIONUI_VIEW_140_VALUE" ]; then
            "$alert_tool" --level caution --title "QuickPDF" \
                "Enter a page range to extract (e.g. 1-5,8 — or 5-1 to reverse)."
            exit 0
        fi
        # Even with a single input, Extract can produce multiple pages/files,
        # so we always use the folder selection (batch style).
        "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "QuickPDF.run.batch"
        ;;
    merge)
        # Count list entries; merging fewer than 2 files is pointless
        if [ "$file_count" -lt 2 ]; then
            "$alert_tool" --level caution --title "QuickPDF" \
                "Merge needs at least 2 files in the list."
            exit 0
        fi
        "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "QuickPDF.run.merge"
        ;;
    *)
        if [ "$file_count" -eq 1 ]; then
            # Single-document 1:1 mode (optimize, decrypt, rotate, repair,
            # metadata, flatten, etc.). Present a proper Save As panel instead
            # of a folder chooser.
            "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "QuickPDF.run.single"
        else
            "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "QuickPDF.run.batch"
        fi
        ;;
esac
