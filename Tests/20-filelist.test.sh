#!/bin/sh
# Tests/20-filelist.test.sh - the file list: adding, dropping, removing, selecting.
#
# None of this is reachable from the older ./test.sh suite, which never runs a
# handler. Everything here goes through the real handler scripts, so the wiring
# between them - which handler reads which variable, which one chains to which -
# is under test too.
#
# The list lives in table 10 and comes back to the handlers as
# OMC_ACTIONUI_TABLE_10_COLUMN_2_ALL_ROWS. sync_file_list is what reproduces that
# round trip; see lib.test.quickpdf.sh for why the harness cannot.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.quickpdf.sh"

section "preconditions"
check_preconditions

text_pdf="$(fixture text.pdf)"
scan_pdf="$(fixture scan.pdf)"

# --------------------------------------------------------------------------
section "the path column this file assumes is the one the handlers read"
# --------------------------------------------------------------------------
# lib.QuickPDF.sh names no constant for the hidden path column - the handlers
# spell the whole variable out, eight times across six files - so
# lib.test.quickpdf.sh has to restate it. That is the one place a second list
# could drift from the first, so it is checked rather than trusted.
#
# The check has to look at EVERY script, not just the shared lib. An earlier
# version greped only lib.QuickPDF.sh, which happens to mention the column
# itself, so it passed while a handler using a different column would have gone
# unnoticed - a check that could not fail at the thing it names.
#
# It works by collecting every column number any script reads, rather than
# confirming the expected one is present: "column 2 appears somewhere" stays
# true when a handler moves to column 3, whereas "the set of columns used is
# exactly {2}" does not.
columns_used=$(/usr/bin/grep -ho "OMC_ACTIONUI_TABLE_${TABLE_ID}_COLUMN_[0-9]*_\(ALL_ROWS\|VALUE\)" \
    "$APP_SCRIPTS"/*.sh 2>/dev/null \
    | /usr/bin/sed "s/.*_COLUMN_\([0-9]*\)_.*/\1/" | /usr/bin/sort -u | /usr/bin/tr '\n' ' ' \
    | /usr/bin/sed 's/ $//')
check "the scripts do read the file list by column" "yes" \
    "$([ -n "$columns_used" ] && echo yes || echo no)"
check "and every one of them uses the column this suite writes" \
    "$TABLE_PATH_COLUMN" "$columns_used"

# --------------------------------------------------------------------------
section "adding a file through the picker"
# --------------------------------------------------------------------------
reset_document
omc_dialog_answer choose_object "$text_pdf"
run_with_list QuickPDF.add.files
check_status "the handler succeeded" 0

check "the file is in the list" "1"         "$(file_count)"
check "with its full path"      "$text_pdf" "$(file_list)"
check "and its display name"    "text.pdf"  "$(file_list_names)"

# Adding to an empty list selects the first row, and does it by the dedicated
# verb - setting a table's VALUE to select a row is the classic mistake and
# would replace the rows with one string.
check "the first row was selected"    "1" "$(ui_calls "omc_select_row")"
check "the rows survived it"          "1" "$(file_count)"
check "the detail buttons came alive" "1" "$(ui_enabled "$REMOVE_BUTTON_ID")"
check "and so did Info"               "1" "$(ui_enabled "$INFO_BUTTON_ID")"

check "the summary names the file"      "yes" "$(contains "$(summary)" "text.pdf")"
check "and reports a page count"        "yes" "$(contains "$(summary)" "Pages")"

# --------------------------------------------------------------------------
section "a second add keeps the first file"
# --------------------------------------------------------------------------
omc_dialog_answer choose_object "$scan_pdf"
run_with_list QuickPDF.add.files
check "both files are listed"    "2"   "$(file_count)"
check "the first is still there" "yes" "$(contains "$(file_list)" "$text_pdf")"
check "and the second arrived"   "yes" "$(contains "$(file_list)" "$scan_pdf")"
check "it resynced instead of reselecting" "1" \
    "$(chain_requested QuickPDF.files.selection.changed)"

# --------------------------------------------------------------------------
section "the same file twice is still one row"
# --------------------------------------------------------------------------
omc_dialog_answer choose_object "$text_pdf"
run_with_list QuickPDF.add.files
check "the duplicate was folded away" "2" "$(file_count)"

# --------------------------------------------------------------------------
section "this is a PDF tool, so only PDFs go in the list"
# --------------------------------------------------------------------------
reset_document
notes="$OMCTEST_WORK/notes.txt"
printf 'not a pdf\n' > "$notes"
omc_dialog_answer choose_object "$notes"
run_with_list QuickPDF.add.files
check "a text file never enters the list" "0" "$(file_count)"

# The positive control: the filter has to admit something, or the check above
# passes for an applet that refuses everything.
omc_dialog_answer choose_object "$text_pdf"
run_with_list QuickPDF.add.files
check "but a pdf does" "1" "$(file_count)"

# The filter is by extension here, deliberately - QuickPDF only ever handles
# PDFs, so it has no content classifier. Pinning that down means a change to
# content sniffing is a decision someone makes rather than a surprise.
reset_document
upper="$OMCTEST_WORK/UPPER.PDF"
/bin/cp "$text_pdf" "$upper"
omc_dialog_answer choose_object "$upper"
run_with_list QuickPDF.add.files
check "the extension test is case-insensitive" "1" "$(file_count)"

# --------------------------------------------------------------------------
section "a folder is searched for the PDFs inside it"
# --------------------------------------------------------------------------
reset_document
tree="$OMCTEST_WORK/tree"
/bin/mkdir -p "$tree/nested"
/bin/cp "$text_pdf" "$tree/one.pdf"
/bin/cp "$text_pdf" "$tree/nested/two.pdf"
printf 'ignore me\n' > "$tree/nested/notes.txt"
omc_dialog_answer choose_object "$tree"
run_with_list QuickPDF.add.files
check "both nested pdfs were found" "2" "$(file_count)"
check "and the text file was not"   "no" "$(contains "$(file_list)" "notes.txt")"

# --------------------------------------------------------------------------
section "dropping files on the table"
# --------------------------------------------------------------------------
reset_document
omc_trigger "$TABLE_ID"
omc_drop "$text_pdf" "$scan_pdf"
run_with_list QuickPDF.files.drop
check_status "the drop handler succeeded" 0
check "both dropped files landed" "2" "$(file_count)"

omc_trigger "$TABLE_ID"
omc_drop "$notes"
run_with_list QuickPDF.files.drop
check "an unusable drop changes nothing" "2" "$(file_count)"

# --------------------------------------------------------------------------
section "a drop carrying no context at all is survivable"
# --------------------------------------------------------------------------
omc_trigger "$TABLE_ID"
run_with_list QuickPDF.files.drop
check_status "the handler exited cleanly" 0
check "and the list is untouched" "2" "$(file_count)"

# --------------------------------------------------------------------------
section "removing the selected file"
# --------------------------------------------------------------------------
reset_document
seed_list "$text_pdf" "$scan_pdf"
check "two files to start" "2" "$(file_count)"

select_file "$text_pdf"
run_with_list QuickPDF.remove.selected
check "one file remains"            "1"          "$(file_count)"
check "and it is the other one"     "$scan_pdf"  "$(file_list)"
check "the pane was told to resync" "1" \
    "$(chain_requested QuickPDF.files.selection.changed)"

# --------------------------------------------------------------------------
section "remove with nothing selected removes nothing"
# --------------------------------------------------------------------------
clear_selection
run_with_list QuickPDF.remove.selected
check "the list is unchanged" "1" "$(file_count)"

# --------------------------------------------------------------------------
section "clear all empties the list and resets the buttons"
# --------------------------------------------------------------------------
reset_document
seed_list "$text_pdf"
run_with_list QuickPDF.clear.all
check "the list is empty" "0" "$(file_count)"
check "the table was emptied by the dedicated verb" "1" \
    "$(ui_calls "omc_table_remove_all_rows")"

# Clearing chains the selection handler, which is what actually disables the
# buttons. Draining the chain is how the test sees the whole user-visible effect
# rather than only the first half of it.
clear_selection
sync_file_list
omc_drain_chain
check "Remove went dead"     "0" "$(ui_enabled "$REMOVE_BUTTON_ID")"
check "Reveal went dead"     "0" "$(ui_enabled "$REVEAL_BUTTON_ID")"
check "Quick Look went dead" "0" "$(ui_enabled "$PREVIEW_BUTTON_ID")"
check "Info went dead"       "0" "$(ui_enabled "$INFO_BUTTON_ID")"

# --------------------------------------------------------------------------
section "selecting a file that has since been deleted"
# --------------------------------------------------------------------------
reset_document
ghost="$OMCTEST_WORK/ghost.pdf"
/bin/cp "$text_pdf" "$ghost"
seed_list "$ghost"
/bin/rm -f "$ghost"
select_file "$ghost"
run_with_list QuickPDF.files.selection.changed
check_status "the handler survived it" 0
check "the summary does not claim a page count" "no" "$(contains "$(summary)" "Pages: 5")"

# --------------------------------------------------------------------------
section "the Quick Look window is handed its path through the pasteboard"
# --------------------------------------------------------------------------
# Two windows, so this is where the second one gets involved. The handoff key is
# global, which is exactly why reset_document has to clear it.
reset_document
seed_list "$text_pdf"
select_file "$text_pdf"
run_with_list QuickPDF.quicklook
check "the path was put on the pasteboard" "$text_pdf" "$(pb_quicklook get)"

omc_window_switch quicklook
omc_run QuickPDF.quicklook.init
check_status "the Quick Look window initialized" 0
check "the preview view was pointed at the file" "$text_pdf" "$(ui_value 200)"
check "and the window was titled"  "yes" "$(contains "$(ui_title)" "text.pdf")"
# Consumed, not left lying around for the next window to pick up.
check "the handoff key was cleared" "" "$(pb_quicklook get)"

# --------------------------------------------------------------------------
section "Quick Look on a file that is gone says so instead of opening blank"
# --------------------------------------------------------------------------
reset_document
gone="$OMCTEST_WORK/gone.pdf"
/bin/cp "$text_pdf" "$gone"
seed_list "$gone"
/bin/rm -f "$gone"
select_file "$gone"
run_with_list QuickPDF.quicklook
check "the user was told"            "1" "$([ "$(alerts_count)" -gt 0 ] && echo 1 || echo 0)"
check "and no window was requested"  "0" "$(chain_asked QuickPDF.quicklook.window)"

# --------------------------------------------------------------------------
section "the engine only gets variables the manifest actually declares"
# --------------------------------------------------------------------------
# The harness is more generous than the engine: it exports whatever a test sets,
# while the engine exports a scanned variable only where the command definition
# asks for it. So a handler reading the whole file list from a command that
# never declares it passes here and comes up empty in the shipped app. This
# compares the two lists rather than trusting either.
readers=$(handlers_reading_file_list)
check "some handler reads the whole list" "yes" \
    "$([ -n "$readers" ] && echo yes || echo no)"
# Indirect readers are the majority here, so if they are missing from the list
# the cross-check below is only inspecting a handful of files.
check "and the indirect readers were found too" "yes" \
    "$(contains "$readers" "QuickPDF.add.files")"

declarers=$(/usr/bin/python3 - "$OMC_APP_BUNDLE_PATH/Contents/Resources/Command.json" \
                               "OMC_ACTIONUI_TABLE_${TABLE_ID}_COLUMN_${TABLE_PATH_COLUMN}_ALL_ROWS" <<'PY'
import json, sys
manifest, wanted = sys.argv[1], sys.argv[2]
doc = json.load(open(manifest))
for command in doc.get("COMMAND_LIST", []):
    if wanted in (command.get("ENVIRONMENT_VARIABLES") or {}):
        print(command.get("COMMAND_ID", ""))
PY
)
check "the manifest declares it somewhere" "yes" \
    "$([ -n "$declarers" ] && echo yes || echo no)"

undeclared=""
for _reader in $readers; do
    case "
$declarers
" in
        *"
$_reader
"*) ;;
        *) undeclared="$undeclared $_reader" ;;
    esac
done
check "every handler that reads the list is given it by the manifest" "" "$undeclared"

# --------------------------------------------------------------------------
section "cumulative: no handler wrote to a view id the window does not declare"
# --------------------------------------------------------------------------
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no bare value write clobbered a table's rows" "" "$(ui_suspect_writes)"
check "the harness detected no misuse" "" "$(ui_errors)"
check "the id set was extracted" "yes" \
    "$([ -s "$OMCTEST_UI/known_ids.txt" ] && echo yes || echo no)"

omctest_end
