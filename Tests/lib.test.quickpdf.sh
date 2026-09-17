# Tests/lib.test.quickpdf.sh - QuickPDF's own test vocabulary, for omctest.
#
# Sourced after omctest.sh by every Tests/*.test.sh file. Holds the things the
# harness has no business knowing: how this applet's table is shaped, and how to
# call into lib.QuickPDF.sh directly.
#
# This suite owns the applet. The remaining ./test.sh suite owns the two
# embedded engines - it proves qpdf and pdfutil agree with each other on real
# documents, and pins the engine behaviors the applet is designed around - and
# nothing there sources the applet's libraries any more. Everything about the
# handlers, the window, and the decisions made before either binary is invoked
# is here.

# omc_control_defaults arrived in API 2. Without it a test would start from a
# blank window, and this applet ships eleven toggles on - a blanked Optimize run
# emits different qpdf flags than a real one.
if [ "${OMCTEST_API_VERSION:-0}" -lt 2 ]; then
    printf 'lib.test.quickpdf: needs omctest API 2 or newer, found %s\n' \
        "${OMCTEST_API_VERSION:-none}" >&2
    exit 1
fi

APP_SCRIPTS="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts"
QPDF_BIN="$OMC_APP_BUNDLE_PATH/Contents/Helpers/qpdf"
PDFUTIL_BIN="$OMC_APP_BUNDLE_PATH/Contents/Helpers/pdfutil"

# ---------------------------------------------------------------------------
# View ids, imported from the applet rather than restated
# ---------------------------------------------------------------------------

# lib.QuickPDF.sh writes them as NAME_ID=10. Two separate -e expressions, not
# one alternation: BSD sed has no \| and would match it literally, importing
# nothing while looking correct.
omctest_import_view_ids() { # <script ...>
    local script
    for script; do
        eval "$(/usr/bin/sed -n \
            -e 's/^\([A-Z][A-Z0-9_]*_ID\)=\([0-9][0-9]*\)$/\1=\2/p' \
            -e 's/^\([A-Z][A-Z0-9_]*_COLUMN\)=\([0-9][0-9]*\)$/\1=\2/p' \
            "$script")"
    done
}

omctest_import_view_ids "$APP_SCRIPTS/lib.QuickPDF.sh"

# The hidden path column. lib.QuickPDF.sh does not name it - the handlers spell
# OMC_ACTIONUI_TABLE_10_COLUMN_2_ALL_ROWS out in full - so unlike PDFUtil's
# TABLE_PATH_COLUMN there is nothing to import, and this is the one id here that
# is restated rather than read from the applet. The check in 20-filelist that
# compares the handlers' own variable name against this value is what keeps the
# two from drifting apart.
TABLE_PATH_COLUMN=2

# Without this guard a renamed constant expands to the empty string, every
# omc_control writes OMC_ACTIONUI_VIEW__VALUE, and the file fails check by check
# with no hint why. With it, it fails once and says which name went missing.
for _required in TABLE_ID SUMMARY_VIEW_ID OPERATION_PICKER_ID RUN_BUTTON_ID \
                 REMOVE_BUTTON_ID GROUP_OPTIMIZE_ID GROUP_ENCRYPT_ID \
                 ENC_STRENGTH_NOTICE_ID ENC_BITS_ID MOVE_UP_BUTTON_ID MOVE_DOWN_BUTTON_ID; do
    eval "_value=\${$_required}"
    if [ -z "$_value" ]; then
        printf 'lib.test.quickpdf: %s did not import from lib.QuickPDF.sh\n' "$_required" >&2
        exit 1
    fi
done
unset _required _value

# ---------------------------------------------------------------------------
# Calling into the applet's library
# ---------------------------------------------------------------------------

# Run a library function in a subshell with lib.QuickPDF.sh loaded.
#
# The subshell keeps the library's own globals - it reassigns QPDF and PDFUTIL
# from the bundle path - out of the test file, and stops a function that calls
# exit from taking the whole file with it. Arguments are expanded by the CALLING
# shell, so a call that has to name one of the library's own constants needs
# quickpdf_eval instead.
quickpdf_call() { # <function> [argument ...]
    (
        . "$APP_SCRIPTS/lib.QuickPDF.sh" >/dev/null 2>&1
        "$@"
    )
}

# As above, but the argument is shell text evaluated INSIDE the subshell, so it
# can name the library's constants and arrays.
quickpdf_eval() { # <shell-text>
    (
        . "$APP_SCRIPTS/lib.QuickPDF.sh" >/dev/null 2>&1
        eval "$1"
    )
}

# The argv build_qpdf_args produced, space-joined.
#
# QPDF_ARGS is a bash array; /bin/sh on macOS is bash 3.2, which has arrays even
# in POSIX mode, so this works in a test file that is otherwise plain sh.
qpdf_args_for() { # <operation>
    quickpdf_eval "build_qpdf_args \"$1\" >/dev/null 2>&1; printf '%s' \"\${QPDF_ARGS[*]}\""
}

qpdf_post_args_for() { # <operation>
    quickpdf_eval "build_qpdf_args \"$1\" >/dev/null 2>&1; printf '%s' \"\${QPDF_POST_ARGS[*]}\""
}

# Is <exact-arg> one of the arguments built for <operation>?
#
# An element match, not a substring of the joined list, because the joined form
# answers the wrong question for exactly the flags worth asserting: "--bits=4"
# is a substring of "--bits=40", and "--print=n" is one of "--print=none". A
# check written against the joined string would report a flag the builder never
# emitted.
#
# The operation and the wanted argument travel as exported variables rather than
# being interpolated into the eval'd text, so a value containing a quote or a $
# cannot end up being parsed as shell.
qpdf_has_arg() { # <operation> <exact-arg> -> yes | no
    export OMCTEST_QPDF_OP="$1" OMCTEST_QPDF_ARG="$2"
    quickpdf_eval '
        build_qpdf_args "$OMCTEST_QPDF_OP" >/dev/null 2>&1
        for _arg in "${QPDF_ARGS[@]}"; do
            if [ "$_arg" = "$OMCTEST_QPDF_ARG" ]; then echo yes; exit 0; fi
        done
        echo no'
}

# The argument at <index> of the list built for <operation>.
#
# Position is load-bearing for one flag: --allow-weak-crypto is global and qpdf
# rejects it once --encrypt has opened its own argument block, so "present
# somewhere" is not the same claim as "present first".
qpdf_arg_at() { # <operation> <index>
    export OMCTEST_QPDF_OP="$1" OMCTEST_QPDF_IDX="$2"
    quickpdf_eval '
        build_qpdf_args "$OMCTEST_QPDF_OP" >/dev/null 2>&1
        printf "%s" "${QPDF_ARGS[$OMCTEST_QPDF_IDX]}"'
}

# Run the argument list the builder produced against the real qpdf, writing to
# <output>. Echoes the exit status.
#
# This is the join the argument checks alone cannot make: a list can be exactly
# what was intended and still be one qpdf refuses. Every flag combination the
# encryption panel can produce is reachable from the UI, so each one gets run.
#
# The argument ORDER mirrors run_qpdf exactly, including QPDF_POST_ARGS between
# the input and the output. Those are how extract passes --pages, and an earlier
# version of this helper dropped them and put the output straight after the
# input - which happened to work because the only caller was encrypt, whose
# POST_ARGS are empty, and would have silently built a wrong command line for
# the first caller that was not.
qpdf_run_built_args() { # <operation> <input> <output>
    export OMCTEST_QPDF_OP="$1" OMCTEST_QPDF_IN="$2" OMCTEST_QPDF_OUT="$3"
    quickpdf_eval '
        build_qpdf_args "$OMCTEST_QPDF_OP" >/dev/null 2>&1
        "$QPDF" "${QPDF_ARGS[@]}" "$OMCTEST_QPDF_IN" "${QPDF_POST_ARGS[@]}" \
            "$OMCTEST_QPDF_OUT" >/dev/null 2>&1
        printf "%s" "$?"'
}

# ---------------------------------------------------------------------------
# The file list: table 10, and the env var the engine derives from it
# ---------------------------------------------------------------------------

# Rows are two tab-separated fields - display name, path - and the path is the
# hidden second column.
file_list() { ui_rows "$TABLE_ID" | /usr/bin/cut -f "$TABLE_PATH_COLUMN"; }
file_list_names() { ui_rows "$TABLE_ID" | /usr/bin/cut -f 1; }
file_count() { ui_row_count "$TABLE_ID"; }

# The value the engine currently holds for a control, read by id.
#
# The obvious `eval echo \$OMC_ACTIONUI_VIEW_${id}_VALUE` expands the control's
# VALUE a second time through the shell: a value containing * would glob against
# the working directory and one containing spaces would be word-split. Every
# value read this way today is a bare word, so it worked - and it would have
# stopped working silently the first time someone reached for a free-text field.
# Here the eval expands only the variable NAME; the value stays inside quotes.
view_value() { # <view-id>
    eval "printf '%s' \"\${OMC_ACTIONUI_VIEW_${1}_VALUE-}\""
}

summary() { ui_value "$SUMMARY_VIEW_ID"; }

# Does the first string contain the second? Answers yes or no, for check.
#
# A function rather than an inline `case`, and not by preference: a case
# pattern's ")" terminates a $( ) command substitution in bash 3.2, so the
# obvious one-liner is a PARSE ERROR rather than a wrong answer - and it fails
# inside the substitution, where the message is easy to miss and the check
# reports a mangled "actual" that looks like an applet bug. The older
# Tests/cases/helpers.sh carries the same helper for the same reason.
contains() { # <haystack> <needle> -> yes | no
    case "$1" in
        *"$2"*) echo yes ;;
        *) echo no ;;
    esac
}

# Every tag a picker actually offers, one per line.
#
# Read out of the UI document rather than retyped in a test, so an option added
# to a picker and forgotten in the code that consumes it is caught by the checks
# that walk this list.
picker_tags() { # <picker-view-id>
    /usr/bin/python3 - "$OMC_APP_BUNDLE_PATH/Contents/Resources/Base.lproj/QuickPDF.json" \
                       "$1" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
wanted = int(sys.argv[2])
def walk(node):
    if isinstance(node, dict):
        if node.get("id") == wanted:
            for option in node.get("properties", {}).get("options", []):
                # {"section": ...} entries are headers: they carry no tag and
                # are never delivered to a handler.
                if isinstance(option, dict) and "tag" in option:
                    print(option["tag"])
            return
        for child in node.values():
            walk(child)
    elif isinstance(node, list):
        for child in node:
            walk(child)
walk(doc)
PY
}

operation_tags() { picker_tags "$OPERATION_PICKER_ID"; }

# Export the file list the way the engine would, from whatever the table now
# holds.
#
# The harness does not do this: it records what a handler wrote to the table,
# but does not feed it back as OMC_ACTIONUI_TABLE_<t>_COLUMN_<c>_ALL_ROWS on the
# next dispatch. Every handler here that acts on more than the selected row
# reads the list through that variable, so without this bridge they would all
# see an empty list and pass for the wrong reason.
#
# Newline-joined, exactly like the engine - which is lossy for a name containing
# a newline. Reproducing the lossiness is the point; a lossless bridge would
# test a world the app never runs in.
sync_file_list() {
    local rows
    rows=$(file_list)
    omctest_setvar "OMC_ACTIONUI_TABLE_${TABLE_ID}_COLUMN_${TABLE_PATH_COLUMN}_ALL_ROWS" "$rows"
}

# Dispatch a handler that reads the whole file list, with that list exported the
# way the engine would export it at dispatch time.
run_with_list() { # <script-stem>
    sync_file_list
    omc_run "$1"
}

# Put rows in the table directly, bypassing the add handlers. Used by the files
# that are about something else, so a defect in add_files_to_table fails
# 20-filelist rather than confusing every section everywhere.
# The field separator is written as printf's \t rather than a literal tab, so
# an editor that helpfully converts tabs to spaces cannot silently turn every
# row into one column.
seed_list() { # <path ...>
    local _p
    for _p in "$@"; do
        printf '%s\t%s\n' "$(/usr/bin/basename "$_p")" "$_p"
    done | "$OMC_OMC_SUPPORT_PATH/omc_dialog_control" \
        "$OMC_ACTIONUI_WINDOW_UUID" "$TABLE_ID" omc_table_set_rows_from_stdin
    sync_file_list
}

select_file() { omc_table_cell "$TABLE_ID" "$TABLE_PATH_COLUMN" "$1"; }
clear_selection() { omc_table_cell "$TABLE_ID" "$TABLE_PATH_COLUMN" ""; }

# ---------------------------------------------------------------------------
# Pasteboard handoffs
# ---------------------------------------------------------------------------

# Both keys are global rather than per-window, so a value left behind by one
# test file would answer the next one's question. Cleared in reset_document.
pb_open_paths() { "$OMC_OMC_SUPPORT_PATH/pasteboard" QUICKPDF_OPEN_PATHS "$@"; }
pb_quicklook() { "$OMC_OMC_SUPPORT_PATH/pasteboard" QUICKPDF_QUICKLOOK_PATH "$@"; }

# Every handler that ends up reading the whole file list, whether it names the
# variable itself or reaches it through a library function it calls.
#
# The resolution is at function level, in Tests/helpers/file_list_readers.py,
# and neither cruder rule works. Grepping the handler files alone sees only the
# minority that name the variable - a reviewer deleted one handler's
# ENVIRONMENT_VARIABLES block from Command.json and the check stayed green.
# "Sources a library that mentions the variable" is the opposite error and
# returns nearly the whole bundle, because every handler sources the core lib.
handlers_reading_file_list() {
    "$OMCTEST_TESTS/helpers/file_list_readers.py" "$APP_SCRIPTS" \
        "OMC_ACTIONUI_TABLE_${TABLE_ID}_COLUMN_${TABLE_PATH_COLUMN}_ALL_ROWS"
}

# ---------------------------------------------------------------------------
# Resetting between sections
# ---------------------------------------------------------------------------

# Put the window back to how it opens: declared control defaults, no table rows,
# no selection, no leftover pasteboard handoff, no recorded window writes.
#
# The pasteboard clear is not optional. It lives in the per-login server and
# outlives the process, so a key left set by an earlier section silently seeds
# the next section's window with a file list it never asked for.
reset_document() {
    omc_control_defaults QuickPDF
    pb_open_paths set "" >/dev/null 2>&1
    pb_quicklook set "" >/dev/null 2>&1
    omc_object ""
    ui_reset
    alerts_reset
    alert_answers_reset
    # Chain history is cumulative across the whole file, so a section asserting
    # "the run did not start" would inherit an earlier section's legitimate run.
    chains_reset
    unset "OMC_ACTIONUI_TABLE_${TABLE_ID}_COLUMN_${TABLE_PATH_COLUMN}_ALL_ROWS"
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# Tests/fixtures is gitignored and generated by Tests/make-fixtures.swift, the
# same generator ./test.sh uses. Generate rather than restate: a second
# generator would be a second set of fixtures to keep in step.
ensure_fixtures() {
    [ -f "$OMCTEST_FIXTURES/text.pdf" ] && return 0
    if [ ! -f "$OMCTEST_TESTS/make-fixtures.swift" ]; then
        printf 'lib.test.quickpdf: no fixtures and no Tests/make-fixtures.swift to build them\n' >&2
        return 1
    fi
    if ! command -v swift >/dev/null 2>&1; then
        printf 'lib.test.quickpdf: fixtures are missing and swift is not available to generate them.\n' >&2
        printf '  Install the Xcode command line tools, or run ./test.sh once.\n' >&2
        return 1
    fi
    /bin/mkdir -p "$OMCTEST_FIXTURES" || return 1
    if ! swift "$OMCTEST_TESTS/make-fixtures.swift" "$OMCTEST_FIXTURES" >/dev/null 2>&1; then
        # A half-written fixture set is worse than none: it fails later, in
        # assertions that look like applet defects.
        /bin/rm -rf "$OMCTEST_FIXTURES"
        printf 'lib.test.quickpdf: fixture generation failed\n' >&2
        return 1
    fi
    return 0
}

# The two engines and the fixtures are preconditions, not things under test.
# Assert them where they are needed so the day one goes missing the failure
# names it, rather than surfacing as twenty unrelated assertion failures.
#
# Contents/Helpers is gitignored, so a fresh checkout genuinely has no binaries;
# that has to fail loudly rather than skip, because a suite that quietly tests
# nothing is worse than one that fails.
check_preconditions() {
    check_exists "fixture precondition: qpdf is embedded"    "$QPDF_BIN"
    check_exists "fixture precondition: pdfutil is embedded" "$PDFUTIL_BIN"
    check "fixture precondition: the fixtures are present" "yes" \
        "$(ensure_fixtures && echo yes || echo no)"
}
