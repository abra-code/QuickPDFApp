#!/bin/bash
# QuickPDF.start.batch.sh - Run button: validate, then route to the right runner
#
# Routing logic:
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
    encrypt)
        user_pw="$OMC_ACTIONUI_VIEW_110_VALUE"
        owner_pw="$OMC_ACTIONUI_VIEW_111_VALUE"
        user_pw_confirm="$OMC_ACTIONUI_VIEW_117_VALUE"
        owner_pw_confirm="$OMC_ACTIONUI_VIEW_119_VALUE"

        # Checked before the empty test, because a mismatch is the more specific
        # diagnosis: it names the field the user got wrong instead of asking for
        # a password they believe they already entered.
        #
        # This is the one class of typo the tool can never recover from. A wrong
        # password on Decrypt just fails against the file, but a wrong password
        # on Encrypt is written into the document: no one can open the result,
        # and nothing here can report what was actually typed. Hence two fields
        # rather than a strength meter or a reveal button.
        if [ "$user_pw" != "$user_pw_confirm" ]; then
            "$alert_tool" --level caution --title "QuickPDF" \
                "The user password and its confirmation do not match.

Retype both fields and try again."
            exit 0
        fi
        if [ "$owner_pw" != "$owner_pw_confirm" ]; then
            "$alert_tool" --level caution --title "QuickPDF" \
                "The owner password and its confirmation do not match.

Retype both fields and try again."
            exit 0
        fi
        if [ -z "$user_pw" ] && [ -z "$owner_pw" ]; then
            "$alert_tool" --level caution --title "QuickPDF" \
                "Enter a user password (and optionally an owner password) before encrypting."
            exit 0
        fi

        # Non-ASCII passwords produce files that cannot be reopened, and qpdf
        # does not reliably say so. Measured against the bundled qpdf 12.3.2,
        # re-opening each result with PDFKit (what Preview and Quick Look use):
        #
        #   "cafe" with an acute e   128: fails   256: fails   qpdf is SILENT
        #   "Strasse" with a sharp s 128: fails   256: opens   qpdf is SILENT
        #   Greek, Japanese          128: opens   256: opens   qpdf warns
        #   emoji                    128: fails   256: fails   qpdf warns
        #
        # So the warning qpdf does emit is anti-correlated with the real
        # failure: the accented-Latin cases most likely for a European user are
        # exactly the ones it writes without complaint, and no key length is
        # safe. Surfacing qpdf's warning would therefore miss them - the check
        # has to be on the password itself, before anything is written.
        #
        # This is the same class of unrecoverable outcome the confirmation
        # fields above exist to prevent: a file nobody can open, reported as a
        # success, with no way to learn what was actually stored.
        if printf '%s%s' "$user_pw" "$owner_pw" | LC_ALL=C /usr/bin/grep -q '[^ -~]'; then
            "$alert_tool" --level caution --title "QuickPDF" \
                "Use only ASCII characters in the password.

PDF password encoding is not handled consistently across readers: an accented or non-Latin password often produces a file that cannot be reopened even with the correct password typed exactly, at every encryption strength. Letters a-z and A-Z, digits, spaces and punctuation are safe."
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
