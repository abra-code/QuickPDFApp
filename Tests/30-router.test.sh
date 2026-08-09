#!/bin/sh
# Tests/30-router.test.sh - the Save button: validation, pre-flight, and where
# the run is sent.
#
# QuickPDF.start.batch refuses bad settings, asks before discarding document
# structure, and chains to one of three runners. 50-library covers the
# predicates it consults one at a time; this file is about the handler that
# consults them - the ORDER of the refusals, the alerts they raise, and the
# command each path chains to.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.quickpdf.sh"

section "preconditions"
check_preconditions

text_pdf="$(fixture text.pdf)"
outlined_pdf="$(fixture outlined.pdf)"
formfilled_pdf="$(fixture form-filled.pdf)"

second_pdf="$OMCTEST_WORK/second.pdf"
/bin/cp "$text_pdf" "$second_pdf"

# Fill in a valid encryption form. Most sections want the password rules
# satisfied so they can test something else.
good_passwords() {
    omc_control "$ENC_USER_PW_ID" "hunter2"
    omc_control "$ENC_USER_PW_CONFIRM_ID" "hunter2"
    omc_control "$ENC_OWNER_PW_ID" ""
    omc_control "$ENC_OWNER_PW_CONFIRM_ID" ""
}

# --------------------------------------------------------------------------
section "an empty list is refused before anything else happens"
# --------------------------------------------------------------------------
reset_document
omc_control "$OPERATION_PICKER_ID" optimize
run_with_list QuickPDF.start.batch
check_status "the handler exits cleanly" 0
check "the user was told"   "1" "$(alerts_mention 'Add some PDF files')"
check "nothing was chained" "0" "$(chain_asked QuickPDF.run.single)"

# --------------------------------------------------------------------------
section "one file goes to the Save As runner, several to the folder runner"
# --------------------------------------------------------------------------
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" repair
run_with_list QuickPDF.start.batch
check "one file goes to run.single" "1" "$(chain_requested QuickPDF.run.single)"
check "with no complaint"           "0" "$(alerts_count)"

reset_document
seed_list "$text_pdf" "$second_pdf"
omc_control "$OPERATION_PICKER_ID" repair
run_with_list QuickPDF.start.batch
check "several files go to run.batch" "1" "$(chain_requested QuickPDF.run.batch)"
check "and not to run.single"         "0" "$(chain_requested QuickPDF.run.single)"

# --------------------------------------------------------------------------
section "extract always goes to the folder runner, even for one file"
# --------------------------------------------------------------------------
# One input can produce several pages, so there is no single name a Save panel
# could confirm.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" extract
omc_control "$EXTRACT_RANGE_FIELD_ID" "1-2"
run_with_list QuickPDF.start.batch
check "one file still goes to run.batch" "1" "$(chain_requested QuickPDF.run.batch)"
check "and not to run.single"            "0" "$(chain_requested QuickPDF.run.single)"

# --------------------------------------------------------------------------
section "extract without a page range is refused"
# --------------------------------------------------------------------------
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" extract
omc_control "$EXTRACT_RANGE_FIELD_ID" ""
run_with_list QuickPDF.start.batch
check "the user was asked for a range" "1" "$(alerts_mention 'page range')"
check "and nothing ran"                "0" "$(chain_asked QuickPDF.run.batch)"

# --------------------------------------------------------------------------
section "merge refuses a single file"
# --------------------------------------------------------------------------
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" merge
run_with_list QuickPDF.start.batch
check "the user was told"     "1" "$(alerts_mention 'at least 2 files')"
check "the run did not start" "0" "$(chain_asked QuickPDF.run.merge)"

reset_document
seed_list "$text_pdf" "$second_pdf"
omc_control "$OPERATION_PICKER_ID" merge
run_with_list QuickPDF.start.batch
check "two files are enough" "1" "$(chain_requested QuickPDF.run.merge)"
check "with no complaint"    "0" "$(alerts_count)"

# --------------------------------------------------------------------------
section "encrypt: a mismatched confirmation is caught before anything is written"
# --------------------------------------------------------------------------
# This is the one class of typo the tool can never recover from. A wrong
# password on Decrypt just fails against the file; a wrong password on Encrypt
# is written INTO the document, and nothing afterwards can report what was
# actually stored.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" encrypt
omc_control "$ENC_USER_PW_ID" "hunter2"
omc_control "$ENC_USER_PW_CONFIRM_ID" "hunter3"
run_with_list QuickPDF.start.batch
check "the user password mismatch is named" "1" "$(alerts_mention 'user password and its confirmation')"
check "and nothing ran"                     "0" "$(chain_asked QuickPDF.run.single)"

reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" encrypt
good_passwords
omc_control "$ENC_OWNER_PW_ID" "owner1"
omc_control "$ENC_OWNER_PW_CONFIRM_ID" "owner2"
run_with_list QuickPDF.start.batch
check "the owner password mismatch is named" "1" "$(alerts_mention 'owner password and its confirmation')"
check "and nothing ran"                      "0" "$(chain_asked QuickPDF.run.single)"

# The positive control: matching confirmations get through, so the two checks
# above are about the mismatch and not about encrypt being broken.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" encrypt
good_passwords
run_with_list QuickPDF.start.batch
check "matching passwords proceed" "1" "$(chain_requested QuickPDF.run.single)"
check "with no complaint"          "0" "$(alerts_count)"

# --------------------------------------------------------------------------
section "encrypt with no password at all is refused"
# --------------------------------------------------------------------------
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" encrypt
omc_control "$ENC_USER_PW_ID" ""
omc_control "$ENC_USER_PW_CONFIRM_ID" ""
omc_control "$ENC_OWNER_PW_ID" ""
omc_control "$ENC_OWNER_PW_CONFIRM_ID" ""
run_with_list QuickPDF.start.batch
check "the user was asked for one" "1" "$(alerts_mention 'Enter a user password')"
check "and nothing ran"            "0" "$(chain_asked QuickPDF.run.single)"

# --------------------------------------------------------------------------
section "a non-ASCII password is refused, because the file would not reopen"
# --------------------------------------------------------------------------
# Measured against the bundled qpdf: an accented Latin password produces a file
# that cannot be reopened with the correct password typed exactly, at every
# strength, and qpdf is SILENT about it. So the check has to be on the password
# itself, before anything is written - qpdf's own warning is anti-correlated
# with the real failure.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" encrypt
accented="caf$(printf '\303\251')"          # cafe with an acute e
omc_control "$ENC_USER_PW_ID" "$accented"
omc_control "$ENC_USER_PW_CONFIRM_ID" "$accented"
run_with_list QuickPDF.start.batch
check "the user was told to use ASCII" "1" "$(alerts_mention 'only ASCII characters')"
check "and nothing ran"                "0" "$(chain_asked QuickPDF.run.single)"

# The positive control: ordinary punctuation is ASCII and must NOT be refused,
# or the rule is just "no passwords".
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" encrypt
omc_control "$ENC_USER_PW_ID" 'p@ss w0rd!#$%'
omc_control "$ENC_USER_PW_CONFIRM_ID" 'p@ss w0rd!#$%'
run_with_list QuickPDF.start.batch
check "punctuation and spaces are fine" "0" "$(alerts_mention 'only ASCII characters')"
check "and the run proceeds"            "1" "$(chain_requested QuickPDF.run.single)"

# --------------------------------------------------------------------------
section "a password past the 127-character cliff is refused"
# --------------------------------------------------------------------------
# AES-256 stores at most 127 bytes. Past that qpdf writes the file, exits 0,
# prints nothing on either stream, and the result cannot be opened with the
# password that created it - the DEFAULT strength silently producing a
# permanently unopenable document.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" encrypt
long_pw="$(/usr/bin/python3 -c 'print("a"*128)')"
check "the fixture password really is 128 characters" "128" "${#long_pw}"
omc_control "$ENC_USER_PW_ID" "$long_pw"
omc_control "$ENC_USER_PW_CONFIRM_ID" "$long_pw"
run_with_list QuickPDF.start.batch
check "the user was told"  "1" "$(alerts_mention '127 characters or fewer')"
check "and nothing ran"    "0" "$(chain_asked QuickPDF.run.single)"

# The boundary from the other side: 127 is legal and must go through. Without
# this the check above would pass for an applet that refuses every password.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" encrypt
ok_pw="$(/usr/bin/python3 -c 'print("a"*127)')"
omc_control "$ENC_USER_PW_ID" "$ok_pw"
omc_control "$ENC_USER_PW_CONFIRM_ID" "$ok_pw"
run_with_list QuickPDF.start.batch
check "127 characters is allowed" "0" "$(alerts_mention '127 characters or fewer')"
check "and the run proceeds"      "1" "$(chain_requested QuickPDF.run.single)"

# --------------------------------------------------------------------------
section "a password never appears in the process arguments"
# --------------------------------------------------------------------------
# NOTE, and this one is a finding rather than a passing assertion: QuickPDF
# passes the password to qpdf on the COMMAND LINE, so it is visible in ps to any
# process on the machine for as long as the run takes. PDFUtil feeds its engine
# on stdin instead. This is recorded as the current behavior rather than
# asserted as correct - see the commit note.
reset_document
omc_control "$OPERATION_PICKER_ID" encrypt
omc_control "$ENC_USER_PW_ID" "correct horse battery staple"
omc_control "$ENC_USER_PW_CONFIRM_ID" "correct horse battery staple"
check "the builder produced arguments" "yes" \
    "$([ -n "$(qpdf_args_for encrypt)" ] && echo yes || echo no)"
check "and today the password IS among them" "yes" \
    "$(contains "$(qpdf_args_for encrypt)" "correct horse battery staple")"

# --------------------------------------------------------------------------
section "the structure pre-flight asks before redrawing a document"
# --------------------------------------------------------------------------
# The alert's buttons are deliberately inverted here: --ok is bound to "Cancel"
# because the alert tool makes --ok the DEFAULT button and this warning is about
# silent, permanent loss, so the safe answer takes the slot a stray Return
# press would hit. The exit codes follow the BUTTONS, not the words:
#   0 = --ok = Cancel        1 = --cancel = Continue
# Getting this backwards would make Return destroy the user's outline, so both
# directions are pinned down here.
reset_document
seed_list "$outlined_pdf"
omc_control "$OPERATION_PICKER_ID" optimize
alert_answer 0                      # the default button, which is Cancel
run_with_list QuickPDF.start.batch
check "the user was asked"       "1"   "$(alerts_mention 'Continue anyway')"
check "the default answer stops the run" "0" "$(chain_asked QuickPDF.run.single)"
check "and the summary says so"  "yes" "$(contains "$(summary)" "Canceled")"

reset_document
seed_list "$outlined_pdf"
omc_control "$OPERATION_PICKER_ID" optimize
alert_answer 1                      # --cancel, which here means Continue
run_with_list QuickPDF.start.batch
check "the other button proceeds to the run" "1" "$(chain_requested QuickPDF.run.single)"

# --------------------------------------------------------------------------
section "an answer that is neither button stops the run and says which"
# --------------------------------------------------------------------------
# 2 other, 3 timed out, 255 the alert tool itself failed. Treating any of these
# as Continue would destroy structure off the back of a dialog the user never
# actually answered.
for _rc in 2 3 255; do
    reset_document
    seed_list "$outlined_pdf"
    omc_control "$OPERATION_PICKER_ID" optimize
    alert_answer "$_rc"
    run_with_list QuickPDF.start.batch
    check "alert result $_rc does not start the run" "0" "$(chain_asked QuickPDF.run.single)"
done

# --------------------------------------------------------------------------
section "the pre-flight only fires when there is something to lose"
# --------------------------------------------------------------------------
# The positive control for the whole section above: a plain document must not be
# interrupted, or the pre-flight is just a dialog on every run.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" optimize
run_with_list QuickPDF.start.batch
check "a plain document is not queried" "0" "$(alerts_mention 'Continue anyway')"
check "and runs straight through"       "1" "$(chain_requested QuickPDF.run.single)"

# A form-filled document has something to lose, so it must be queried.
reset_document
seed_list "$formfilled_pdf"
omc_control "$OPERATION_PICKER_ID" optimize
alert_answer 1
run_with_list QuickPDF.start.batch
check "a document with form fields is queried" "1" "$(alerts_mention 'Continue anyway')"

# Turning off image recompression is the documented way to keep the structure,
# so with it off there is nothing to warn about.
reset_document
seed_list "$outlined_pdf"
omc_control "$OPERATION_PICKER_ID" optimize
omc_control "$OPT_RECOMPRESS_IMAGES_ID" false
run_with_list QuickPDF.start.batch
check "with recompression off there is no warning" "0" "$(alerts_mention 'Continue anyway')"
check "and the run proceeds"                       "1" "$(chain_requested QuickPDF.run.single)"

# An operation that does not redraw must not ask either, whatever the document
# carries.
reset_document
seed_list "$outlined_pdf"
omc_control "$OPERATION_PICKER_ID" repair
run_with_list QuickPDF.start.batch
check "repair keeps the outline, so it does not ask" "0" "$(alerts_mention 'Continue anyway')"

# --------------------------------------------------------------------------
section "cumulative: no handler wrote to a view id the window does not declare"
# --------------------------------------------------------------------------
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no bare value write clobbered a table's rows" "" "$(ui_suspect_writes)"
check "the harness detected no misuse" "" "$(ui_errors)"
check "the id set was extracted" "yes" \
    "$([ -s "$OMCTEST_UI/known_ids.txt" ] && echo yes || echo no)"

omctest_end
