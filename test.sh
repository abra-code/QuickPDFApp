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
# Deliberately NO `set -e`. A test runner is the worst possible place for it: it
# ends the run at the first command that returns non-zero, which in a suite is a
# routine event, and it does so silently - no FAIL line, later cases never run,
# and the result is indistinguishable from an ordinary failure. Verified here by
# dropping a case file containing a single `false` into Tests/cases: the whole
# run stopped after printing that file's header, with no summary and five case
# files never executed. It also makes the obvious `out=$(tool ...); code=$?`
# unwritable. Failures are counted explicitly below instead.
#
# Every case file in Tests/cases/*.sh is sourced with access to the helpers and
# the variables defined below.

# Setup failures are fatal and explicit. Without `set -e` nothing stops on its
# own, so every step the rest of the run depends on is checked here rather than
# left to produce confusing symptoms twenty assertions later.
die() {
    echo "ERROR: $*" >&2
    exit 1
}

cd "$(dirname "$0")" || die "cannot cd to the script's directory"

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
    mkdir -p "$FIX" || die "cannot create $FIX"
    if ! swift Tests/make-fixtures.swift "$FIX"; then
        rm -rf "$FIX"   # a half-written fixture set is worse than none
        die "fixture generation failed - see the swift output above"
    fi
fi
# Generated or pre-existing, the fixtures the cases name have to be there. A
# missing one otherwise surfaces as a pile of unrelated assertion failures
# pointing at the tools rather than at the empty file they were handed.
for _f in text.pdf scan.pdf form-filled.pdf outlined.pdf; do
    [ -s "$FIX/$_f" ] || die "fixture $FIX/$_f is missing or empty - delete $FIX and re-run to regenerate"
done

rm -rf "$TMP"   || die "cannot clear $TMP"
mkdir -p "$TMP" || die "cannot create $TMP"

# Failure counter. A case may run an assertion inside a pipeline, and a pipeline
# stage is a subshell whose variable updates the parent never sees - so counting
# in a shell variable silently loses those failures. Count in a file instead.
#
# Two files on purpose. $FAILLOG is one line per failure and exists only to be
# counted; $FAILDETAIL keeps the messages, so a run that fails leaves something
# readable behind instead of only a number - which matters when the run happened
# somewhere nobody was watching.
FAILLOG="$TMP/.failures"
FAILDETAIL="$TMP/failures.log"
: > "$FAILLOG"    || die "cannot write $FAILLOG"
: > "$FAILDETAIL" || die "cannot write $FAILDETAIL"
fail() {
    echo "FAIL: $*" >&2
    echo x >> "$FAILLOG"
    printf '%s\n' "$*" >> "$FAILDETAIL"
}

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

# For a case file's own SETUP steps - a mkdir, a chmod, writing a stub - as
# opposed to the thing under test. Without `set -e` those run unchecked, and the
# negative helpers below are the ones that then lie: expect_fail, expect_nogrep
# and expect_nogrep_all all pass when a command produces no output, which is
# exactly what happens when its input was never created. A failed setup would
# therefore be reported as a passing assertion.
#
# Use as `require mkdir -p "$V" || return` - the `|| return` abandons the rest of
# the case, which is the honest response to setup that did not happen, and the
# subshell in the case loop keeps that contained.
require() {
    if ! "$@"; then
        fail "setup failed: $*"
        return 1
    fi
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

# Each case runs in a SUBSHELL so it cannot leak into the next one. The
# isolation is not academic: optimize-pipeline.sh sources lib.QuickPDF.sh at its
# top level, and the library reassigns $QPDF and $PDFUTIL from the bundle path -
# without the subshell every later case would be measuring whichever binaries the
# library resolved rather than the ones this runner checked.
#
# Completion is detected with a MARKER, not with the case's exit status. Without
# `set -e` a sourced file's status is just the status of its last command, which
# says nothing about how far it got: a case ending on the ordinary
# `[ -n "$x" ] && rm -f "$x"` idiom returns non-zero having run everything, and a
# case calling `exit 0` halfway returns zero having run half. Writing the marker
# as the subshell's last act inverts both - it is reached only if control got
# past the end of the sourced file, and `exit` from inside the case skips it.
#
# All of this works because failures are counted in a FILE: a subshell's
# variables die with it, but its appends to $FAILLOG do not.
#
# The case files are collected into an array under `nullglob` rather than
# iterated straight off the pattern. Without it a Tests/cases holding no .sh at
# all leaves the literal string "Tests/cases/*.sh" as the single loop item, and
# the run reports a sourcing failure for a file that does not exist instead of
# the real problem, which is that there are no cases. The array is also what
# makes the comparison below trustworthy - re-counting with `ls` would re-expand
# the same pattern and hit the same trap.
#
# nullglob is saved and restored rather than switched off, so the setting the
# caller had is the setting the case files run under.
nullglob_state="$(shopt -p nullglob)"
shopt -s nullglob
casefiles=(Tests/cases/*.sh)
eval "$nullglob_state"

CASE_DONE="$TMP/.case-complete"
ran=0
for casefile in "${casefiles[@]}"; do
    echo "== $casefile =="
    rm -f "$CASE_DONE"
    ( . "$casefile"; : > "$CASE_DONE" )
    if [ ! -e "$CASE_DONE" ]; then
        fail "$casefile called exit before reaching its end - its remaining assertions never ran"
    fi
    ran=$((ran + 1))
done
rm -f "$CASE_DONE"

# Re-globbed and compared by CONTENT, not by count: one file added and another
# removed nets to zero, so a count comparison would miss exactly the mid-run
# change it is here to catch.
shopt -s nullglob
final=(Tests/cases/*.sh)
eval "$nullglob_state"
if [ "${casefiles[*]}" != "${final[*]}" ]; then
    fail "Tests/cases changed while the run was in progress - ran [${casefiles[*]}], now holds [${final[*]}]"
fi
if [ "$ran" -eq 0 ]; then
    fail "no case files found in Tests/cases - the suite tested nothing"
fi

FAILURES=$(wc -l < "$FAILLOG" | tr -d ' ')
if [ "$FAILURES" -gt 0 ]; then
    echo "" >&2
    echo "$FAILURES test(s) failed. Details in $FAILDETAIL:" >&2
    sed 's/^/  /' "$FAILDETAIL" >&2
    exit 1
fi
echo "All tests passed. ($ran case files)"
