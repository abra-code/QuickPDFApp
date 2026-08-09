# two-engine-rationale.sh - why this bundle ships two PDF engines.
#
# QuickPDF's README justifies embedding pdfutil alongside qpdf with one claim:
# qpdf cannot recompress a JPEG scan and pdfutil can. That is a statement about
# the two binaries, and it is the premise the whole Optimize design rests on -
# if it stopped being true, the image stage, the structure warning it forces,
# and the fallback logic behind it would all be dead weight.
#
# The app's own pipeline is tested in its omctest suite, which drives
# optimize_file through the real handlers. This file tests only the engine
# behavior that pipeline is built around, with no applet code involved.

size() { /usr/bin/stat -f %z "$1" 2>/dev/null || echo 0; }

# The flags the app's structural pass sends. Written out rather than sourced,
# because the claim is about what a structural rewrite can and cannot do, not
# about one exact command line.
qpdf_structural() { # <input> <output>
    "$QPDF" --compress-streams=y --recompress-flate --compression-level=9 \
        --object-streams=generate --remove-unreferenced-resources=yes "$1" "$2"
}

O="$TMP/two-engine"
require mkdir -p "$O" || return

# --- the fixture really is what the argument assumes -----------------------
#
# qpdf skips DCTDecode images, which is the entire premise below. If a future
# macOS stopped passing the JPEG through, the fixture would quietly become
# Flate, qpdf alone WOULD shrink it, and the comparison would stop testing
# anything while still passing.
expect_grep_all "DCTDecode" "$QPDF" --json "$FIX/scan.pdf"

before=$(size "$FIX/scan.pdf")
[ "$before" -gt 0 ] || fail "the scan fixture is empty"

# --- qpdf alone: essentially no change on a JPEG scan ----------------------
#
# Measured at ~99% of the original. Anything above 90% counts as "no change", so
# ordinary qpdf version drift does not turn into a false failure.
expect_ok qpdf_structural "$FIX/scan.pdf" "$O/qpdf-only.pdf"
qpdfonly=$(size "$O/qpdf-only.pdf")
if [ "$qpdfonly" -lt $(( before * 90 / 100 )) ]; then
    fail "qpdf alone shrank the JPEG scan to $qpdfonly of $before bytes - either the fixture is no longer DCTDecode or qpdf learned to recompress, and either way the case for bundling pdfutil needs rechecking"
fi

# --- pdfutil: a large, real reduction on the same file ---------------------
#
# Measured at ~39% of the original; require at least a 25% saving so the
# assertion means something without being brittle.
expect_ok "$PDFUTIL" reduce -q 60 -r 100 --force -o "$O/reduced.pdf" "$FIX/scan.pdf"
reduced=$(size "$O/reduced.pdf")
if [ "$reduced" -gt $(( before * 75 / 100 )) ]; then
    fail "pdfutil barely shrank the scan: $before -> $reduced bytes"
fi
if [ "$reduced" -ge "$qpdfonly" ]; then
    fail "pdfutil ($reduced) did not beat the qpdf-only pass ($qpdfonly) on a JPEG scan - the second engine is earning nothing"
fi

# Shrinking by destroying the document would satisfy both size checks, so the
# result has to survive the other engine's parser intact.
expect_eq 0 "$(qpdf_check_code "$O/reduced.pdf")" "qpdf --check on pdfutil's reduced scan"
expect_eq "2" "$("$QPDF" --show-npages "$O/reduced.pdf")" "page count after pdfutil reduce"

# --- ...and on text, the roles reverse -------------------------------------
#
# The structural pass is lossless, which is why the README steers text documents
# at the qpdf-only path. Nothing rasterizes, so the text layer must survive
# exactly.
expect_ok qpdf_structural "$FIX/text.pdf" "$O/qpdf-text.pdf"
expect_eq 0 "$(qpdf_check_code "$O/qpdf-text.pdf")" "qpdf --check on the structural pass over text"
expect_eq "5" "$("$QPDF" --show-npages "$O/qpdf-text.pdf")" "page count after the structural pass"
expect_grep "PAGE-1-MARKER" "$PDFUTIL" text "$O/qpdf-text.pdf"
expect_grep "PAGE-5-MARKER" "$PDFUTIL" text "$O/qpdf-text.pdf"
