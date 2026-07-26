#!/bin/bash
# test.sh - cross-tool tests for the QuickPDF app bundle.
#
# QuickPDF embeds two independent PDF engines, qpdf and pdfutil, and its Optimize
# operation runs them as a pipeline. This suite tests what neither tool's own test
# suite structurally can: that the two agree with each other, that each can read
# what the other writes, and that the app's real pipeline works end to end.
#
# Bash, not sh: the app's lib.QuickPDF.sh uses bash arrays, and the optimize case
# sources it to drive the same code path the app runs.
#
# Every case file in Tests/cases/*.sh is sourced with access to the helpers and
# the variables defined below.

set -e

cd "$(dirname "$0")"

# The app bundle under test. Override to test a bundle elsewhere, e.g. a staged
# copy or an installed /Applications/QuickPDF.app.
APP="${QUICKPDF_APP:-$PWD/QuickPDF.app}"
QPDF="$APP/Contents/Helpers/qpdf"
PDFUTIL="$APP/Contents/Helpers/pdfutil"
LIB="$APP/Contents/Resources/Scripts/lib.QuickPDF.sh"

FIX="Tests/fixtures"
TMP="Tests/tmp"

# Unlike the optional cross-checker in pdfutil's own suite, both binaries are
# REQUIRED here - they are the subject of these tests, not a convenience. A
# missing helper is a hard error, never a silent skip, because a suite that
# quietly tests nothing is worse than one that fails.
missing=""
[ -x "$QPDF" ]    || missing="$missing\n  qpdf:    $QPDF"
[ -x "$PDFUTIL" ] || missing="$missing\n  pdfutil: $PDFUTIL"
[ -f "$LIB" ]     || missing="$missing\n  lib:     $LIB"
if [ -n "$missing" ]; then
    printf 'ERROR: the app bundle is not populated. Missing:%b\n' "$missing" >&2
    echo "" >&2
    echo "Contents/Helpers is gitignored, so a fresh checkout has no binaries yet." >&2
    echo "Build and embed them first:  ./update_quickpdf.sh --with-qpdf" >&2
    echo "Or point at another bundle:  QUICKPDF_APP=/path/to/QuickPDF.app $0" >&2
    exit 1
fi

echo "app:     $APP"
echo "qpdf:    $("$QPDF" --version 2>/dev/null | head -1)"
echo "pdfutil: $("$PDFUTIL" --version 2>/dev/null | head -1)"

if [ ! -d "$FIX" ]; then
    if ! command -v swift >/dev/null 2>&1; then
        echo "ERROR: fixtures are missing and 'swift' is not available to generate them." >&2
        echo "       Install the Xcode command line tools, or copy in a $FIX directory." >&2
        exit 1
    fi
    echo "Generating fixtures..."
    mkdir -p "$FIX"
    swift Tests/make-fixtures.swift "$FIX"
fi

rm -rf "$TMP"
mkdir -p "$TMP"

# Failure counter. A case may run an assertion inside a pipeline, and a pipeline
# stage is a subshell whose variable updates the parent never sees - so counting
# in a shell variable silently loses those failures. Count in a file instead. The
# message itself has already gone to stderr, so one line per failure is enough.
FAILLOG="$TMP/.failures"
: > "$FAILLOG"
fail() { echo "FAIL: $*" >&2; echo x >> "$FAILLOG"; }

# Assertion helpers. All wrap the command in an `if`, so a failing command never
# trips `set -e`; failures are counted and reported at the end.
expect_ok()   { if ! "$@" >/dev/null 2>&1; then fail "expected success: $*"; fi; }
expect_fail() { if "$@" >/dev/null 2>&1; then fail "expected failure: $*"; fi; }
expect_code() {
    want="$1"; shift
    if "$@" >/dev/null 2>&1; then got=0; else got=$?; fi
    if [ "$got" != "$want" ]; then fail "expected exit $want, got $got: $*"; fi
}
expect_grep() {
    pat="$1"; shift
    if ! "$@" 2>/dev/null | grep -q -- "$pat"; then fail "expected /$pat/ from: $*"; fi
}
expect_nogrep() {
    pat="$1"; shift
    if "$@" 2>/dev/null | grep -q -- "$pat"; then fail "unexpected /$pat/ from: $*"; fi
}

# As above but matching stdout AND stderr. Required whenever the interesting text
# is a diagnostic: qpdf writes its WARNING and ERROR lines to stderr, so the
# stdout-only forms above would pass vacuously against them.
expect_grep_all() {
    pat="$1"; shift
    if ! "$@" 2>&1 | grep -q -- "$pat"; then fail "expected /$pat/ in stdout+stderr from: $*"; fi
}
expect_nogrep_all() {
    pat="$1"; shift
    if "$@" 2>&1 | grep -q -- "$pat"; then fail "unexpected /$pat/ in stdout+stderr from: $*"; fi
}

# Compare two values, reporting both on mismatch - the whole point of a cross-tool
# suite is what the two tools each said, so never report just "mismatch".
expect_eq() {
    want="$1"; got="$2"; what="$3"
    if [ "$want" != "$got" ]; then fail "$what: expected [$want], got [$got]"; fi
}

# qpdf --check exit codes: 0 clean, 3 warnings only, 2 errors. Structural errors
# are failures; warnings are asserted explicitly by the cases that expect them,
# so a change in warning status is noticed rather than tolerated.
qpdf_check_code() {
    "$QPDF" --check "$@" >/dev/null 2>&1 && echo 0 || echo $?
}

for casefile in Tests/cases/*.sh; do
    echo "== $casefile =="
    . "$casefile"
done

FAILURES=$(wc -l < "$FAILLOG" | tr -d ' ')
if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES test(s) failed." >&2
    exit 1
fi
echo "All tests passed."
