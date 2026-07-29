# The Optimize pipeline - the app's own two-engine code path, end to end.
#
# This is the one place in production where both engines touch the same file:
# optimize_file runs `pdfutil reduce` for images, then the qpdf structural pass,
# then the linearize keep-if-smaller two-pass. Rather than reimplementing that
# sequence here, the case sources the app's lib.QuickPDF.sh and calls the real
# build_qpdf_args and optimize_file, so what is tested is the shipping logic.
#
# build_qpdf_args reads UI state only from OMC_ACTIONUI_VIEW_<id>_VALUE variables,
# which is what makes this drivable without the app running. The control IDs come
# from lib.QuickPDF.sh: 70 linearize, 71 compress streams, 72 recompress images,
# 73 JPEG quality, 74 object streams, 75 remove unreferenced, 76 downsample,
# 77 DPI.

# Sourcing lib.QuickPDF.sh assigns its own QPDF and PDFUTIL, overwriting the
# runner's, so remember what this suite intends to test before sourcing and then
# confirm the library resolved the same two binaries. Otherwise every measurement
# below could silently be about some other bundle.
suite_qpdf="$QPDF"
suite_pdfutil="$PDFUTIL"

# lib.QuickPDF.sh locates the helpers relative to the bundle.
export OMC_APP_BUNDLE_PATH="$APP"
. "$LIB"

expect_eq "$suite_qpdf"    "$QPDF"    "lib.QuickPDF.sh resolved qpdf"
expect_eq "$suite_pdfutil" "$PDFUTIL" "lib.QuickPDF.sh resolved pdfutil"

# set_optimize_ui <linearize> <compress> <recompress> <quality> <objstreams> <unref> <downsample> <dpi>
set_optimize_ui() {
    export OMC_ACTIONUI_VIEW_70_VALUE="$1"
    export OMC_ACTIONUI_VIEW_71_VALUE="$2"
    export OMC_ACTIONUI_VIEW_72_VALUE="$3"
    export OMC_ACTIONUI_VIEW_73_VALUE="$4"
    export OMC_ACTIONUI_VIEW_74_VALUE="$5"
    export OMC_ACTIONUI_VIEW_75_VALUE="$6"
    export OMC_ACTIONUI_VIEW_76_VALUE="$7"
    export OMC_ACTIONUI_VIEW_77_VALUE="$8"
}

size() { /usr/bin/stat -f %z "$1" 2>/dev/null || echo 0; }

# --- argument construction -------------------------------------------------
#
# Check the translation from UI state to qpdf flags before running anything, so a
# pipeline failure below is not ambiguous between "bad args" and "bad execution".
set_optimize_ui true true true 85 generate true true 100
build_qpdf_args optimize
expect_eq "1"   "$QPDF_RECOMPRESS_IMAGES" "recompress images flag"
expect_eq "85"  "$QPDF_JPEG_QUALITY"      "jpeg quality"
expect_eq "100" "$QPDF_DOWNSAMPLE_DPI"    "downsample dpi"
expect_eq "1"   "$QPDF_LINEARIZE"         "linearize flag"
case "${QPDF_ARGS[*]}" in
    *"--object-streams=generate"*) ;;
    *) fail "optimize args missing --object-streams=generate: ${QPDF_ARGS[*]}" ;;
esac
case "${QPDF_ARGS[*]}" in
    *"--compress-streams=y"*) ;;
    *) fail "optimize args missing --compress-streams=y: ${QPDF_ARGS[*]}" ;;
esac

# Recompression off must NOT invoke pdfutil at all - that is the promise the
# README makes about the structure-preserving qpdf-only path.
set_optimize_ui false true false 85 generate true false 0
build_qpdf_args optimize
expect_eq "0" "$QPDF_RECOMPRESS_IMAGES" "recompress images off"
expect_eq "0" "$QPDF_LINEARIZE"         "linearize off"

# --- the scan: why the two-engine pipeline exists -------------------------
#
# The fixture's images must really be JPEG. qpdf skips DCTDecode images, which is
# the entire premise below; if a future macOS stopped passing the JPEG through, the
# fixture would silently become Flate, qpdf alone would shrink it, and the
# comparison would quietly stop testing anything. Assert the premise directly.
expect_grep_all "DCTDecode" "$QPDF" --json "$FIX/scan.pdf"

before=$(size "$FIX/scan.pdf")

# qpdf-only path: essentially no change on a JPEG scan. This is the README's
# justification for bundling a second engine at all, so it is worth asserting
# rather than assuming. Measured at ~99% of the original; allow anything above 90%
# so normal qpdf version drift does not turn into a false failure.
set_optimize_ui false true false 85 generate true false 0
build_qpdf_args optimize
if out=$(optimize_file "$FIX/scan.pdf" "$TMP/opt-scan-qpdfonly.pdf"); then code=0; else code=$?; fi
expect_eq 0 "$code" "optimize_file exit status, qpdf-only on the scan"
qpdfonly=$(size "$TMP/opt-scan-qpdfonly.pdf")
if [ "$qpdfonly" -lt $(( before * 90 / 100 )) ]; then
    fail "qpdf alone shrank the JPEG scan to $qpdfonly of $before bytes; the fixture is probably no longer DCTDecode, which would invalidate the reduce comparison"
fi

# Both stages: a large, real reduction. Measured at ~39% of the original; require
# at least a 25% saving so the assertion means something without being brittle.
set_optimize_ui true true true 60 generate true true 100
build_qpdf_args optimize
if out=$(optimize_file "$FIX/scan.pdf" "$TMP/opt-scan.pdf"); then code=0; else code=$?; fi
after=$(size "$TMP/opt-scan.pdf")

expect_eq 0 "$code" "optimize_file exit status on the scan fixture"
if [ "$after" -gt $(( before * 75 / 100 )) ]; then
    fail "reduce+qpdf pipeline barely shrank the scan: $before -> $after bytes"
fi
# And it must beat the qpdf-only path, which is the whole point of the two stages.
if [ "$after" -ge "$qpdfonly" ]; then
    fail "two-stage pipeline ($after) did not beat qpdf-only ($qpdfonly) on a JPEG scan"
fi
# The result must still be a valid PDF with both pages intact - a pipeline that
# shrinks a file by destroying it would otherwise pass the size checks.
expect_eq 0 "$(qpdf_check_code "$TMP/opt-scan.pdf")" "qpdf --check on optimize output"
expect_eq "2" "$("$QPDF" --show-npages "$TMP/opt-scan.pdf")" "page count after optimize"

# --- qpdf-only path preserves the text layer ------------------------------
#
# With recompression off nothing rasterizes, so text must survive exactly. (The
# reduce stage redraws pages, which is why the README steers text documents at
# the qpdf-only path.)
set_optimize_ui false true false 85 generate true false 0
build_qpdf_args optimize
if out=$(optimize_file "$FIX/text.pdf" "$TMP/opt-text.pdf"); then code=0; else code=$?; fi
expect_eq 0 "$code" "optimize_file exit status on the text fixture"
expect_eq 0 "$(qpdf_check_code "$TMP/opt-text.pdf")" "qpdf --check on qpdf-only optimize output"
expect_grep "PAGE-1-MARKER" "$PDFUTIL" text "$TMP/opt-text.pdf"
expect_grep "PAGE-5-MARKER" "$PDFUTIL" text "$TMP/opt-text.pdf"
expect_eq "5" "$("$QPDF" --show-npages "$TMP/opt-text.pdf")" "page count after qpdf-only optimize"

# --- linearize keep-if-smaller --------------------------------------------
#
# With linearize requested the pipeline runs a second pass and keeps it only if it
# did not grow the file. Either outcome is correct, so assert the invariant that
# actually matters: whatever is delivered is valid, complete, and no larger than
# the non-linearized result.
set_optimize_ui false true false 85 generate true false 0
build_qpdf_args optimize
if out=$(optimize_file "$FIX/text.pdf" "$TMP/opt-plain.pdf"); then plain_code=0; else plain_code=$?; fi
plain=$(size "$TMP/opt-plain.pdf")

set_optimize_ui true true false 85 generate true false 0
build_qpdf_args optimize
if out=$(optimize_file "$FIX/text.pdf" "$TMP/opt-lin.pdf"); then lin_code=0; else lin_code=$?; fi
lin=$(size "$TMP/opt-lin.pdf")

expect_eq 0 "$plain_code" "optimize_file exit (linearize off)"
# 0 or 3 are both acceptable: a kept linearized pass may carry qpdf warnings.
case "$lin_code" in
    0|3) ;;
    *) fail "optimize_file with linearize returned $lin_code (expected 0 or 3)" ;;
esac
if [ "$lin" -gt "$plain" ]; then
    fail "linearize keep-if-smaller kept a larger file: $lin > $plain bytes"
fi
expect_grep "PAGE-3-MARKER" "$PDFUTIL" text "$TMP/opt-lin.pdf"
expect_eq "5" "$("$QPDF" --show-npages "$TMP/opt-lin.pdf")" "page count after linearize pass"

# --- failure handling -----------------------------------------------------
#
# A non-PDF input must be reported as a failure, not silently produce an empty
# output file the batch loop would treat as a success.
set_optimize_ui false true true 85 generate true true 100
build_qpdf_args optimize
printf 'this is not a pdf\n' > "$TMP/notapdf.pdf"
if out=$(optimize_file "$TMP/notapdf.pdf" "$TMP/opt-bad.pdf"); then bad_code=0; else bad_code=$?; fi
if [ "$bad_code" = 0 ]; then
    fail "optimize_file reported success on a non-PDF input"
fi

# --- the image stage did not help, so qpdf's own optimizer gets a turn ------
#
# pdfutil exiting 0 does not mean pdfutil helped. Its Quartz filter re-encodes
# only images it rescales, so it can hand back something no better than the
# input; current builds notice a result that grew and return the original bytes
# instead. Either way optimize_file must spot it and fall back rather than
# passing the untouched images to the structural pass.

# image_stage_helped is the predicate that decides. Test it on real files.
printf 'aaaaaaaaaaaaaaaa' > "$TMP/isz-before"
printf 'aaaa'             > "$TMP/isz-smaller"
printf 'aaaaaaaaaaaaaaaa' > "$TMP/isz-equal"
printf 'aaaaaaaaaaaaaaaaaaaaaaaa' > "$TMP/isz-bigger"
: > "$TMP/isz-empty"
if ! image_stage_helped "$TMP/isz-before" "$TMP/isz-smaller"; then
    fail "image_stage_helped rejected a genuinely smaller file"
fi
if image_stage_helped "$TMP/isz-before" "$TMP/isz-equal"; then
    fail "image_stage_helped accepted an equal-sized file"
fi
if image_stage_helped "$TMP/isz-before" "$TMP/isz-bigger"; then
    fail "image_stage_helped accepted a larger file"
fi
if image_stage_helped "$TMP/isz-before" "$TMP/isz-empty"; then
    fail "image_stage_helped accepted a 0-byte result"
fi
if image_stage_helped "$TMP/isz-before" "$TMP/isz-nonexistent"; then
    fail "image_stage_helped accepted a missing result"
fi

# Whether the fallback is wired up is a question about the qpdf command line, not
# about how well anything compressed - qpdf skips ICC/JPEG images, so on the very
# scans where pdfutil declines it may save nothing at all. Stub both engines and
# read the arguments the pipeline actually built.
stub_dir="$TMP/stubs"
require /bin/mkdir -p "$stub_dir" || return

# A pdfutil that "succeeds" while returning the input unchanged - what a current
# build does when it declines its own result.
cat > "$stub_dir/pdfutil-noop" <<'STUB'
#!/bin/sh
out=""; in=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -q|-r|-m) shift 2 ;;
        reduce|--force) shift ;;
        *) in="$1"; shift ;;
    esac
done
cp "$in" "$out"
STUB

# ...and one that genuinely shrinks, to prove the fallback stays off when the
# image stage did its job.
cat > "$stub_dir/pdfutil-shrink" <<'STUB'
#!/bin/sh
out=""; in=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -q|-r|-m) shift 2 ;;
        reduce|--force) shift ;;
        *) in="$1"; shift ;;
    esac
done
# Smaller than the input but still a real PDF, so the qpdf pass can read it.
cp "$in" "$out"
/usr/bin/truncate -s $(( $(/usr/bin/stat -f %z "$in") - 1 )) "$out"
STUB

# A qpdf that records its argument list and produces a valid output file.
cat > "$stub_dir/qpdf-record" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" > "$QPDF_ARGS_LOG"
# The output path is the last argument; the input is the one before POST_ARGS.
for a in "$@"; do last="$a"; done
cp "$QPDF_STUB_SOURCE" "$last"
STUB
# A stub that is not executable fails to run, and the assertions below read the
# argument log it never wrote - which is an absent file, not a wrong one, so they
# would pass on emptiness.
require /bin/chmod +x "$stub_dir/pdfutil-noop" "$stub_dir/pdfutil-shrink" "$stub_dir/qpdf-record" || return

export QPDF_ARGS_LOG="$TMP/qpdf-args.log"
export QPDF_STUB_SOURCE="$FIX/text.pdf"
real_qpdf="$QPDF"
real_pdfutil="$PDFUTIL"

# Recompress on, and the image stage returns the file unchanged: the qpdf pass
# must pick up --optimize-images.
QPDF="$stub_dir/qpdf-record"
PDFUTIL="$stub_dir/pdfutil-noop"
set_optimize_ui false true true 60 generate true true 150
build_qpdf_args optimize
ignored=$(optimize_file "$FIX/scan.pdf" "$TMP/fallback-on.pdf" 2>/dev/null)
expect_grep "--optimize-images" /bin/cat "$QPDF_ARGS_LOG"
expect_grep "--jpeg-quality=60" /bin/cat "$QPDF_ARGS_LOG"

# The same run with an image stage that DID shrink must not add the flag: qpdf's
# optimizer would then be re-encoding images pdfutil already handled.
PDFUTIL="$stub_dir/pdfutil-shrink"
build_qpdf_args optimize
ignored=$(optimize_file "$FIX/scan.pdf" "$TMP/fallback-off.pdf" 2>/dev/null)
expect_nogrep "--optimize-images" /bin/cat "$QPDF_ARGS_LOG"

# And with the image stage switched off entirely there is nothing to fall back
# from, so the flag must stay absent however the run goes.
set_optimize_ui false true false 60 generate true true 150
build_qpdf_args optimize
ignored=$(optimize_file "$FIX/scan.pdf" "$TMP/fallback-nostage.pdf" 2>/dev/null)
expect_nogrep "--optimize-images" /bin/cat "$QPDF_ARGS_LOG"

QPDF="$real_qpdf"
PDFUTIL="$real_pdfutil"
unset QPDF_ARGS_LOG QPDF_STUB_SOURCE
