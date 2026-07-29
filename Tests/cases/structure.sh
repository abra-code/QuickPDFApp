# Structural validation - qpdf --check over the output of every pdfutil verb.
#
# pdfutil writes through PDFKit, so its own suite can only ask PDFKit whether
# PDFKit's output is good. qpdf is a wholly independent parser with a strict
# structural checker, which makes it the useful second opinion. Both tools ship in
# this bundle, so a file produced by one is routinely fed to the other.
#
# qpdf --check exit codes: 0 clean, 3 warnings only, 2 errors.

V="$TMP/verbs"
# Checked: every negative assertion below (expect_nogrep_all "ERROR" ...) passes
# vacuously against a file that was never written, so an unchecked mkdir here
# would turn this whole case green rather than red.
require mkdir -p "$V" || return

# check_verb <label> <output-file> <pdfutil args...>
# Runs the verb, then requires a completely clean qpdf --check on its output.
check_verb() {
    label="$1"; outf="$2"; shift 2
    if ! "$PDFUTIL" "$@" >/dev/null 2>&1; then
        fail "$label: pdfutil verb itself failed"
        return
    fi
    code=$(qpdf_check_code "$outf")
    if [ "$code" != 0 ]; then
        fail "$label: qpdf --check returned $code (0 expected): $("$QPDF" --check "$outf" 2>&1 | grep -iE 'WARNING|ERROR' | head -1)"
    fi
}

check_verb merge     "$V/merge.pdf"  merge -o "$V/merge.pdf" "$FIX/text.pdf" "$FIX/form-filled.pdf"
check_verb pages     "$V/pages.pdf"  pages --extract 2-3 -o "$V/pages.pdf" "$FIX/text.pdf"
check_verb rotate    "$V/rot.pdf"    rotate 90 -o "$V/rot.pdf" "$FIX/text.pdf"
check_verb crop      "$V/crop.pdf"   crop --margins 10,10,10,10 -o "$V/crop.pdf" "$FIX/text.pdf"
check_verb metadata  "$V/meta.pdf"   metadata --set title=CrossTool -o "$V/meta.pdf" "$FIX/text.pdf"
check_verb flatten   "$V/flat.pdf"   flatten -o "$V/flat.pdf" "$FIX/form-filled.pdf"
check_verb reduce    "$V/red.pdf"    reduce --dpi 100 -o "$V/red.pdf" "$FIX/scan.pdf"
check_verb watermark "$V/wm.pdf"     watermark --text DRAFT -o "$V/wm.pdf" "$FIX/text.pdf"
check_verb pdfa      "$V/pdfa.pdf"   pdfa -o "$V/pdfa.pdf" "$FIX/text.pdf"
check_verb frompages "$V/from.pdf"   frompages -o "$V/from.pdf" "$FIX/text.pdf"

# linearize is the one exception, and it is a real finding rather than a tolerated
# nuisance. PDFKit's linearizer writes a hint table qpdf considers inconsistent:
# --check reports "File is linearized" and then warns about shared-object hint
# entries, exiting 3 (warnings, no errors). The file is valid and genuinely
# linearized; only the hint table is imperfect, and pdfutil cannot fix that
# without replacing PDFKit's writer.
#
# Asserted exactly, not skipped: exit 3 with warnings but no ERROR line. If it
# ever becomes clean this fails and the exception can be deleted; if it ever
# degrades into real errors it fails too.
expect_ok "$PDFUTIL" linearize -o "$V/lin.pdf" "$FIX/text.pdf"
expect_eq 3 "$(qpdf_check_code "$V/lin.pdf")" "qpdf --check on pdfutil linearize (known hint-table warnings)"
# "File is linearized" is on stdout; the WARNING lines are on stderr, so the
# combined-stream forms are required here for the assertions to mean anything.
expect_grep "File is linearized" "$QPDF" --check "$V/lin.pdf"
expect_grep_all "hint table" "$QPDF" --check "$V/lin.pdf"
expect_nogrep_all "ERROR" "$QPDF" --check "$V/lin.pdf"

# By contrast, qpdf's own linearizer produces a hint table qpdf is happy with -
# which is what confirms the warnings above come from the writer, not from
# --check being unreasonable about linearized files in general.
expect_ok "$QPDF" --linearize "$FIX/text.pdf" "$V/qlin.pdf"
expect_eq 0 "$(qpdf_check_code "$V/qlin.pdf")" "qpdf --check on qpdf's own linearize"

# --- content agreement, not just structural validity ----------------------
#
# A file can be structurally clean and still have lost its content, so check that
# the two tools see the same page counts after pdfutil transforms.
expect_eq "5" "$("$QPDF" --show-npages "$FIX/text.pdf")" "qpdf page count of the fixture"
expect_eq "2" "$("$QPDF" --show-npages "$V/pages.pdf")" "qpdf page count after pdfutil extract 2-3"
expect_eq "6" "$("$QPDF" --show-npages "$V/merge.pdf")" "qpdf page count after pdfutil merge (5+1)"
expect_grep "pages: 2" "$PDFUTIL" info "$V/pages.pdf"
expect_grep "pages: 6" "$PDFUTIL" info "$V/merge.pdf"

# flatten: pdfutil burns the field value into the page, and qpdf confirms the
# interactive widget is gone from the structure rather than merely hidden.
expect_grep "Alice" "$PDFUTIL" text "$V/flat.pdf"
if [ "$("$QPDF" --json "$V/flat.pdf" 2>/dev/null | grep -c '/Widget')" != 0 ]; then
    fail "flatten: qpdf still sees a /Widget annotation in the flattened output"
fi
