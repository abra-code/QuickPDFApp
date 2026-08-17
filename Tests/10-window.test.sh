#!/bin/sh
# Tests/10-window.test.sh - the window as it opens, the panel switcher, and the
# encryption-strength notice.
#
# The older ./test.sh suite never runs a handler, so none of this is covered
# there: it tests lib.QuickPDF.sh's pure functions and the two engines against
# each other, and stops below the UI.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.quickpdf.sh"

section "preconditions"
check_preconditions

# --------------------------------------------------------------------------
section "the window opens in its declared state"
# --------------------------------------------------------------------------
reset_document

# The structural control for every assertion below that reads a control value:
# if the extraction silently matched nothing, this is the check that says so
# rather than letting twenty later checks pass against an empty window.
check "the declared defaults loaded" "yes" \
    "$([ "${OMCTEST_DEFAULTS_APPLIED:-0}" -gt 25 ] && echo yes || echo no)"
check "the operation picker starts on Optimize" "optimize" \
    "$OMC_ACTIONUI_VIEW_60_VALUE"

# These are the toggles a blanked window would get wrong, and getting them wrong
# changes the qpdf command line rather than just the pixels.
check "recompress images ships on"       "true"  "$(view_value "$OPT_RECOMPRESS_IMAGES_ID")"
check "downsample ships on"              "true"  "$(view_value "$OPT_DOWNSAMPLE_ID")"
# Linearize is the one Optimize toggle that ships OFF: it reorders objects for
# progressive display and grows a well-optimized file, so a panel whose stated
# job is reducing size must not do it unasked.
check "linearize ships off"              "false" "$(view_value "$OPT_LINEARIZE_ID")"
check "allow-modify ships OFF by omission" "false" "$(view_value "$ENC_ALLOW_MODIFY_ID")"
# ENC_DEFAULT_BITS is not an id, so the _ID import does not pick it up; read it
# out of the library itself rather than restating 256 here.
check "the encryption strength starts at the library's default" \
    "$(quickpdf_eval 'printf %s "$ENC_DEFAULT_BITS"')" \
    "$(view_value "$ENC_BITS_ID")"

omc_run QuickPDF.init
check_status "init succeeded" 0
check "the file list starts empty" "0" "$(file_count)"
check "the table was actively emptied, not merely never filled" "1" \
    "$(ui_calls "omc_table_remove_all_rows")"
# Not just "qpdf" - the version has to have come back from the real binary.
check "the summary names the qpdf version" "yes" "$(contains "$(summary)" "qpdf ")"

# --------------------------------------------------------------------------
section "the declared defaults are the ones the argument builder sees"
# --------------------------------------------------------------------------
# This is the whole reason a test must not start from a blank window. With the
# toggles blanked, Optimize builds a different qpdf command line than the one a
# user gets, and every assertion about it describes software nobody is running.
# The image settings do not become qpdf flags - they drive the pdfutil reduce
# pre-pass - so they are read back from the globals build_qpdf_args sets.
reset_document
decided() { quickpdf_eval "build_qpdf_args optimize >/dev/null 2>&1; printf '%s' \"\$$1\""; }

args="$(qpdf_args_for optimize)"
check "the builder produced a command line" "yes" "$([ -n "$args" ] && echo yes || echo no)"
check "the streams toggle reached qpdf"     "yes" "$(contains "$args" "--compress-streams=y")"
check "and the default run does not linearize" "no" \
    "$(qpdf_has_arg optimize --linearize)"
check "recompressing images was decided on" "1"   "$(decided QPDF_RECOMPRESS_IMAGES)"
check "at the declared jpeg quality"        "85"  "$(decided QPDF_JPEG_QUALITY)"
check "and the declared downsample dpi"     "150" "$(decided QPDF_DOWNSAMPLE_DPI)"

# The contrast, made explicit. This is the whole argument for starting from the
# declared defaults: blank the window the way omc_reset_controls does and the
# same code decides to do different work.
omc_reset_controls
check "a blanked window would not recompress" "0" "$(decided QPDF_RECOMPRESS_IMAGES)"
# A blanked toggle reads "" where the shipped one reads "false", so this is a
# different branch of the same comparison than the default-window check above -
# and the one that catches a builder testing for "not off" instead of "on".
check "and would not linearize"               "no" "$(qpdf_has_arg optimize --linearize)"
check "so its command line differs"           "no" \
    "$([ "$args" = "$(qpdf_args_for optimize)" ] && echo yes || echo no)"

# --------------------------------------------------------------------------
section "choosing an operation shows exactly one panel"
# --------------------------------------------------------------------------
reset_document
omc_fire QuickPDF.operation.changed "$OPERATION_PICKER_ID" encrypt
check_status "the handler succeeded" 0

check "the encrypt panel is visible" "1" "$(ui_visible "$GROUP_ENCRYPT_ID")"
check "the optimize panel is hidden" "0" "$(ui_visible "$GROUP_OPTIMIZE_ID")"

# Counting the visible ones is not enough on its own: an untouched panel reads
# empty rather than "0", so a switcher that shows the right panel and hides
# nothing still leaves exactly one panel reading "1". The count with teeth is of
# panels explicitly hidden, because a panel left over from the previous
# operation stays on screen otherwise.
panel_ids="$GROUP_OPTIMIZE_ID $GROUP_ENCRYPT_ID $GROUP_DECRYPT_ID $GROUP_ROTATE_ID \
$GROUP_EXTRACT_ID $GROUP_SPLIT_ID $GROUP_MERGE_ID $GROUP_REPAIR_ID \
$GROUP_METADATA_ID $GROUP_FLATTEN_ID"
visible_panels=0
hidden_panels=0
total_panels=0
for _panel in $panel_ids; do
    total_panels=$((total_panels + 1))
    case "$(ui_visible "$_panel")" in
        1) visible_panels=$((visible_panels + 1)) ;;
        0) hidden_panels=$((hidden_panels + 1)) ;;
    esac
done
check "all ten panels were named"               "10" "$total_panels"
check "exactly one settings panel is visible"   "1"  "$visible_panels"
check "and every other one was actively hidden" "9"  "$hidden_panels"

# --------------------------------------------------------------------------
section "every operation the picker offers has a panel of its own"
# --------------------------------------------------------------------------
# Walking the picker's own options rather than a list retyped here: an operation
# added to the UI and forgotten in the switcher's case statement leaves the
# previous panel on screen, which looks like the app ignoring the choice.
reset_document
tags="$(operation_tags)"
check "the picker's options were read" "yes" \
    "$([ "$(printf '%s\n' "$tags" | /usr/bin/wc -w)" -ge 10 ] && echo yes || echo no)"

no_panel=""
for _op in $tags; do
    reset_document
    omc_fire QuickPDF.operation.changed "$OPERATION_PICKER_ID" "$_op"
    _shown=0
    for _panel in $panel_ids; do
        [ "$(ui_visible "$_panel")" = "1" ] && _shown=$((_shown + 1))
    done
    [ "$_shown" = "1" ] || no_panel="$no_panel $_op"
done
check "every offered operation shows exactly one panel" "" "$no_panel"

# The positive control: the loop above has to be able to find something. An
# operation the switcher does not know shows no panel at all.
reset_document
omc_fire QuickPDF.operation.changed "$OPERATION_PICKER_ID" no-such-operation
_shown=0
for _panel in $panel_ids; do
    [ "$(ui_visible "$_panel")" = "1" ] && _shown=$((_shown + 1))
done
check "an unknown operation shows no panel" "0" "$_shown"

# --------------------------------------------------------------------------
section "the encryption-strength notice explains only what needs explaining"
# --------------------------------------------------------------------------
# The default is the strongest option and needs no notice. Each weaker one
# trades something different away, so the text is per-option.
reset_document
omc_fire QuickPDF.encrypt.bits.changed "$ENC_BITS_ID" 256
check "256-bit says nothing"    ""      "$(ui_value "$ENC_STRENGTH_NOTICE_ID")"
check "and the notice is hidden" "true" "$(ui_prop "$ENC_STRENGTH_NOTICE_ID" hidden)"

omc_fire QuickPDF.encrypt.bits.changed "$ENC_BITS_ID" 128
check "128-bit warns about the password length" "yes" \
    "$(contains "$(ui_value "$ENC_STRENGTH_NOTICE_ID")" "first 32 characters")"
check "and the notice is shown" "false" "$(ui_prop "$ENC_STRENGTH_NOTICE_ID" hidden)"

omc_fire QuickPDF.encrypt.bits.changed "$ENC_BITS_ID" 40
check "40-bit says it is easily broken" "yes" \
    "$(contains "$(ui_value "$ENC_STRENGTH_NOTICE_ID")" "easily broken")"
check "and the notice is shown" "false" "$(ui_prop "$ENC_STRENGTH_NOTICE_ID" hidden)"

# --------------------------------------------------------------------------
section "going back to the default clears the notice, not just hides it"
# --------------------------------------------------------------------------
# ActionUI's "hidden" maps to SwiftUI .hidden(), which still reserves the
# element's layout space and keeps its last value. Hiding the three-line 40-bit
# notice without clearing it leaves a three-line invisible gap, and everything
# below shifts according to which options the user happened to browse through.
omc_fire QuickPDF.encrypt.bits.changed "$ENC_BITS_ID" 40
check "the long notice is there to start with" "yes" \
    "$(contains "$(ui_value "$ENC_STRENGTH_NOTICE_ID")" "easily broken")"
omc_fire QuickPDF.encrypt.bits.changed "$ENC_BITS_ID" 256
check "the text was cleared, not merely hidden" "" "$(ui_value "$ENC_STRENGTH_NOTICE_ID")"
check "and it is hidden as well"                "true" \
    "$(ui_prop "$ENC_STRENGTH_NOTICE_ID" hidden)"

# --------------------------------------------------------------------------
section "an empty strength falls back to the default rather than warning"
# --------------------------------------------------------------------------
reset_document
omc_fire QuickPDF.encrypt.bits.changed "$ENC_BITS_ID" ""
check "no notice for a missing value" "" "$(ui_value "$ENC_STRENGTH_NOTICE_ID")"

# --------------------------------------------------------------------------
section "cumulative: no handler wrote to a view id the window does not declare"
# --------------------------------------------------------------------------
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no bare value write clobbered a table's rows" "" "$(ui_suspect_writes)"
check "the harness detected no misuse" "" "$(ui_errors)"
check "the id set was extracted" "yes" \
    "$([ -s "$OMCTEST_UI/known_ids.txt" ] && echo yes || echo no)"

omctest_end
