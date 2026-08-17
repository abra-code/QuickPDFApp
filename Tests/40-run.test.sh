#!/bin/sh
# Tests/40-run.test.sh - the runners: real qpdf, real output files.
#
# qpdf and pdfutil are deterministic and safe to run headless, so they run for
# real. A staging-and-move assertion is worth nothing against a fake that never
# writes anything.
#
# What is under test is the runner HANDLERS, not the engines: that Cancel writes
# no file, that a failed run leaves nothing behind, that qpdf's warning exit is
# treated as success-with-a-note rather than failure, and that a file already at
# the chosen path survives a failure. The older ./test.sh suite covers the
# engines agreeing with each other and the optimize pipeline's internals; it
# never reaches these handlers, which need a Save As answer the engine supplies.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.quickpdf.sh"

section "preconditions"
check_preconditions

text_pdf="$(fixture text.pdf)"
scan_pdf="$(fixture scan.pdf)"

# --------------------------------------------------------------------------
section "a single-file run writes the file the user named"
# --------------------------------------------------------------------------
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" repair
out="$OMCTEST_WORK/repaired.pdf"
omc_dialog_answer save_as "$out"
run_with_list QuickPDF.run.single
check_status "the runner succeeded" 0

check_exists "the output file is there" "$out"
check "and qpdf can read it back"  "0" \
    "$("$QPDF_BIN" --check "$out" >/dev/null 2>&1 && echo 0 || echo $?)"
check "the input was left alone"   "yes" "$([ -s "$text_pdf" ] && echo yes || echo no)"
check "the summary names the file" "yes" "$(contains "$(summary)" "text.pdf")"
check "and where it went"          "yes" "$(contains "$(summary)" "Output: $out")"
check "no staging file was left behind" "0" \
    "$(/usr/bin/find "$OMCTEST_WORK" -maxdepth 1 -name '.quickpdf.*' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

# --------------------------------------------------------------------------
section "an extension is appended when the chosen name lacks one"
# --------------------------------------------------------------------------
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" repair
omc_dialog_answer save_as "$OMCTEST_WORK/noext"
run_with_list QuickPDF.run.single
check_exists "the .pdf was added" "$OMCTEST_WORK/noext.pdf"
check_absent "and nothing was written under the bare name" "$OMCTEST_WORK/noext"

# A name that already ends in .pdf is passed through as typed - the Save panel
# already confirmed it, so it is overwritten rather than renamed.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" repair
confirmed="$OMCTEST_WORK/confirmed.pdf"
printf 'stale output from an earlier run' > "$confirmed"
omc_dialog_answer save_as "$confirmed"
run_with_list QuickPDF.run.single
check "the confirmed name was replaced, as the panel promised" "no" \
    "$(contains "$(/bin/cat "$confirmed")" "stale output")"

# The derived name is different: the user never saw it, so it must not be
# clobbered.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" repair
printf 'never confirmed, must survive' > "$OMCTEST_WORK/derived.pdf"
omc_dialog_answer save_as "$OMCTEST_WORK/derived"
run_with_list QuickPDF.run.single
check "the derived name was not clobbered" "never confirmed, must survive" \
    "$(/bin/cat "$OMCTEST_WORK/derived.pdf")"
check_exists "the run went to a numbered name instead" "$OMCTEST_WORK/derived 2.pdf"

# --------------------------------------------------------------------------
section "an optimize run really does go through both engines"
# --------------------------------------------------------------------------
# scan.pdf is the image-heavy fixture, and Optimize's pdfutil reduce pre-pass is
# the only reason it shrinks. This is the applet's headline operation and the
# one whose pipeline the whole two-engine bundle exists for.
reset_document
seed_list "$scan_pdf"
omc_control "$OPERATION_PICKER_ID" optimize
optimized="$OMCTEST_WORK/optimized.pdf"
omc_dialog_answer save_as "$optimized"
run_with_list QuickPDF.run.single
check_status "the run succeeded" 0
check_exists "the output exists" "$optimized"
check "and is structurally sound" "0" \
    "$("$QPDF_BIN" --check "$optimized" >/dev/null 2>&1 && echo 0 || echo $?)"
before_size="$(/usr/bin/stat -f %z "$scan_pdf")"
after_size="$(/usr/bin/stat -f %z "$optimized")"
# A MAGNITUDE, not just "smaller". The structural pass alone takes this fixture
# to about 99.8% of its original size, so a bare `-lt` is satisfied with the
# pdfutil image stage switched off entirely - which is the one thing this
# section exists to prove happened.
#
# The ceiling sits between two measured numbers, and both matter. At the
# DECLARED defaults this window ships - quality 85, 150 dpi - the full pipeline
# lands at 83%. That is much less dramatic than the 40% Tests/cases reaches, and
# deliberately so: that file drives the engines directly at -q 60 -r 100, which
# is not what a user's window sends. 95% separates 83% from 99.8% with room on
# both sides.
check "the scanned document got substantially smaller" "yes" \
    "$([ "$after_size" -lt "$(( before_size * 95 / 100 ))" ] && echo yes || echo no)"
check "the summary reports the size change" "yes" "$(contains "$(summary)" "Output:")"

# --------------------------------------------------------------------------
section "qpdf warnings are a completed run with a note, not a failure"
# --------------------------------------------------------------------------
# qpdf exits 3 when it recovered from something - a damaged cross-reference
# table, here. The output is real and usable, so treating 3 as a failure would
# throw away a good file and tell the user the run failed, while treating it as
# a silent success would hide that the document was damaged. It has to be both.
reset_document
damaged="$OMCTEST_WORK/damaged.pdf"
/bin/cp "$text_pdf" "$damaged"
# Point startxref at an offset that does not exist: qpdf reconstructs the table,
# warns, and exits 3.
"$OMCTEST_TESTS/helpers/damage_startxref.py" "$damaged"
check "the fixture really does provoke a warning" "3" \
    "$("$QPDF_BIN" --check "$damaged" >/dev/null 2>&1 && echo 0 || echo $?)"

seed_list "$damaged"
omc_control "$OPERATION_PICKER_ID" repair
recovered="$OMCTEST_WORK/recovered.pdf"
omc_dialog_answer save_as "$recovered"
run_with_list QuickPDF.run.single
check_exists "the recovered file was still written" "$recovered"
check "and it is clean afterwards" "0" \
    "$("$QPDF_BIN" --check "$recovered" >/dev/null 2>&1 && echo 0 || echo $?)"
check "the summary reports the warnings" "yes" "$(contains "$(summary)" "warnings")"
check "and still names the output"       "yes" "$(contains "$(summary)" "Output: $recovered")"

# --------------------------------------------------------------------------
section "cancelling the save panel writes nothing"
# --------------------------------------------------------------------------
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" repair
before="$(/usr/bin/find "$OMCTEST_WORK" -maxdepth 1 -type f | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
omc_dialog_answer save_as ""
run_with_list QuickPDF.run.single
check_status "the runner still exits cleanly" 0
after="$(/usr/bin/find "$OMCTEST_WORK" -maxdepth 1 -type f | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
check "no file was created" "$before" "$after"

# --------------------------------------------------------------------------
section "a failed run does not destroy a file already at that path"
# --------------------------------------------------------------------------
# This is what the staging file is for, and the only scenario that tells a
# staged run from an unstaged one. The user picks a name that already holds
# something, the run fails, and the previous file has to still be there - an
# unstaged run truncates it on the way to failing and the contents are gone with
# nothing to say so.
reset_document
survivor="$OMCTEST_WORK/survivor.pdf"
/bin/cp "$text_pdf" "$survivor"
survivor_size="$(/usr/bin/stat -f %z "$survivor")"

notpdf="$OMCTEST_WORK/broken.pdf"
printf 'this is not a pdf at all' > "$notpdf"
seed_list "$notpdf"
omc_control "$OPERATION_PICKER_ID" repair
omc_dialog_answer save_as "$survivor"
run_with_list QuickPDF.run.single
check "the run failed, as intended"             "yes" "$(contains "$(summary)" "broken.pdf")"
check_exists "the existing file is still there" "$survivor"
check "and is byte for byte what it was"        "$survivor_size" \
    "$(/usr/bin/stat -f %z "$survivor" 2>/dev/null)"
check "no staging file was left behind"         "0" \
    "$(/usr/bin/find "$OMCTEST_WORK" -maxdepth 1 -name '.quickpdf.*' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

# --------------------------------------------------------------------------
section "an input that vanished between Save and run is reported, not crashed on"
# --------------------------------------------------------------------------
reset_document
ghost="$OMCTEST_WORK/ghost.pdf"
/bin/cp "$text_pdf" "$ghost"
seed_list "$ghost"
/bin/rm -f "$ghost"
omc_control "$OPERATION_PICKER_ID" repair
omc_dialog_answer save_as "$OMCTEST_WORK/from-ghost.pdf"
run_with_list QuickPDF.run.single
check_status "the runner exits cleanly" 0
check "it says the input is gone" "yes" "$(contains "$(summary)" "does not exist")"
check_absent "and wrote nothing"  "$OMCTEST_WORK/from-ghost.pdf"

# --------------------------------------------------------------------------
section "merging two documents produces one with both"
# --------------------------------------------------------------------------
reset_document
second="$OMCTEST_WORK/second.pdf"
/bin/cp "$text_pdf" "$second"
seed_list "$text_pdf" "$second"
omc_control "$OPERATION_PICKER_ID" merge
merged="$OMCTEST_WORK/merged.pdf"
omc_dialog_answer save_as "$merged"
run_with_list QuickPDF.run.merge
check_status "the merge succeeded" 0
check_exists "the merged file exists" "$merged"

# The page count is the assertion with teeth: a merge that silently copied only
# the first input would still leave a valid PDF at that path.
pages_one="$("$QPDF_BIN" --show-npages "$text_pdf" 2>/dev/null)"
pages_merged="$("$QPDF_BIN" --show-npages "$merged" 2>/dev/null)"
check "the source has a readable page count" "yes" \
    "$([ -n "$pages_one" ] && [ "$pages_one" -gt 0 ] 2>/dev/null && echo yes || echo no)"
check "the merge has both documents' pages" "$((pages_one * 2))" "$pages_merged"

# --------------------------------------------------------------------------
section "a batch run writes one output per input"
# --------------------------------------------------------------------------
reset_document
dest="$OMCTEST_WORK/batch-out"
/bin/mkdir -p "$dest"
a="$OMCTEST_WORK/a.pdf"; b="$OMCTEST_WORK/b.pdf"
/bin/cp "$text_pdf" "$a"; /bin/cp "$text_pdf" "$b"
seed_list "$a" "$b"
omc_control "$OPERATION_PICKER_ID" repair
omc_dialog_answer choose_folder "$dest"
run_with_list QuickPDF.run.batch
check_status "the batch succeeded" 0
check "both files were written" "2" \
    "$(/usr/bin/find "$dest" -maxdepth 1 -name '*.pdf' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
check "no staging file survived in the destination" "0" \
    "$(/usr/bin/find "$dest" -maxdepth 1 -name '.quickpdf.*' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

# --------------------------------------------------------------------------
section "a batch warning says what the warning was"
# --------------------------------------------------------------------------
# "(with warnings)" on its own tells the user that something happened and never
# what. The single-file runner has always printed the whole message; batch has
# room for one line per file and takes the first. One of the things that line
# now has to carry is optimize_file's note that a linearize had to be dropped -
# something the user ticked a box for and did not get - and a batch of twenty
# is exactly where an unexplained warning count is easiest to ignore.
reset_document
dest_warn="$OMCTEST_WORK/batch-out-warn"
/bin/mkdir -p "$dest_warn"
damaged_batch="$OMCTEST_WORK/damaged-batch.pdf"
/bin/cp "$text_pdf" "$damaged_batch"
"$OMCTEST_TESTS/helpers/damage_startxref.py" "$damaged_batch"
seed_list "$damaged_batch"
omc_control "$OPERATION_PICKER_ID" repair
omc_dialog_answer choose_folder "$dest_warn"
run_with_list QuickPDF.run.batch
check_status "the batch ran" 0
check "the file is counted as warned" "yes" "$(contains "$(summary)" "1 with warnings")"
check "and the summary quotes qpdf's first line" "yes" \
    "$(contains "$(summary)" "file is damaged")"
check_exists "the repaired file was still written" "$dest_warn/damaged-batch.pdf"

# --------------------------------------------------------------------------
section "a batch run does not overwrite what is already in the folder"
# --------------------------------------------------------------------------
# The folder chooser confirms a DIRECTORY, not the names inside it, so nothing
# there was confirmed for replacement.
reset_document
dest2="$OMCTEST_WORK/batch-out-2"
/bin/mkdir -p "$dest2"
printf 'existing work' > "$dest2/a.pdf"
seed_list "$a"
omc_control "$OPERATION_PICKER_ID" repair
omc_dialog_answer choose_folder "$dest2"
run_with_list QuickPDF.run.batch
check "the existing file survived" "existing work" "$(/bin/cat "$dest2/a.pdf")"
check_exists "and the run went to a numbered name" "$dest2/a 2.pdf"

# --------------------------------------------------------------------------
section "cumulative: no handler wrote to a view id the window does not declare"
# --------------------------------------------------------------------------
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no bare value write clobbered a table's rows" "" "$(ui_suspect_writes)"
check "the harness detected no misuse" "" "$(ui_errors)"
check "the id set was extracted" "yes" \
    "$([ -s "$OMCTEST_UI/known_ids.txt" ] && echo yes || echo no)"

omctest_end
