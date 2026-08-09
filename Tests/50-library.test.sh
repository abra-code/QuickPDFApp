#!/bin/sh
# Tests/50-library.test.sh - the library functions the handlers are built from.
#
# The other files dispatch handlers and read the window. This one calls into
# lib.QuickPDF.sh directly, because several of its decisions are not observable
# from the outside: which qpdf flags an encryption strength produces, whether
# the image stage earned its place, and what the pre-flight would have found.
# Driving a handler and looking at the result cannot distinguish "built the
# right command line" from "built a different one that happened to work".
#
# These assertions used to live in ./test.sh, which sourced the library and
# called the same functions. They moved here when that suite was narrowed to
# the embedded engines, and they are stronger for it: omctest starts every
# section from the window's DECLARED control defaults rather than a blank
# environment, so what the builder sees is what a user's window holds.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.quickpdf.sh"

section "preconditions"
check_preconditions

text_pdf="$(fixture text.pdf)"
scan_pdf="$(fixture scan.pdf)"
outlined_pdf="$(fixture outlined.pdf)"
formfilled_pdf="$(fixture form-filled.pdf)"

# No trailer of ui_unknown_writes / ui_suspect_writes checks in this file, on
# purpose. Those ask whether a handler wrote to a view id the document does not
# declare, and nothing here dispatches a handler - the answers would be empty by
# construction, which is the definition of a check that cannot fail.

# --------------------------------------------------------------------------
section "an untouched encryption panel writes AES-256"
# --------------------------------------------------------------------------
# ActionUI selects a picker's first option when the document declares none, and
# an untouched picker then reports "" rather than a tag. Both spellings of "the
# user did not choose" have to land on the same key length, and they disagreed
# for two days in July 2026 - the constant said 256 while the notice handler
# said 128.
reset_document
omc_control "$ENC_USER_PW_ID" "hunter2"
omc_control "$ENC_USER_PW_CONFIRM_ID" "hunter2"

# The declared default first, then the empty-picker fallback inside the builder.
# They are different code paths: one is a value the document supplies, the other
# is the `[ -z "$bits" ] && bits=$ENC_DEFAULT_BITS` line.
check "the picker's declared default is the library's default" \
    "$(quickpdf_eval 'printf %s "$ENC_DEFAULT_BITS"')" \
    "$(view_value "$ENC_BITS_ID")"

for _bits_value in "" 256; do
    omc_control "$ENC_BITS_ID" "$_bits_value"
    _label="${_bits_value:-an untouched picker}"
    check "$_label asks for 256-bit keys" "yes" "$(qpdf_has_arg encrypt --bits=256)"
    # --use-aes=y is a 128-bit-only flag: 256-bit is AES by construction, and
    # qpdf rejects the combination.
    check "$_label does not ask for AES twice"  "no" "$(qpdf_has_arg encrypt --use-aes=y)"
    # The weak-crypto override is scoped to the one RC4 strength on offer, so
    # that its presence stays an accurate signal rather than boilerplate.
    check "$_label needs no weak-crypto override" "no" \
        "$(qpdf_has_arg encrypt --allow-weak-crypto)"
done

# The list is not merely what was intended - it is one qpdf accepts, and the
# file it writes really is /R 6.
omc_control "$ENC_BITS_ID" ""
_out="$OMCTEST_WORK/enc-default.pdf"
check "qpdf accepts the default encryption arguments" "0" \
    "$(qpdf_run_built_args encrypt "$text_pdf" "$_out")"
check "and the result is AES-256" "1" \
    "$("$QPDF_BIN" --show-encryption --password=hunter2 "$_out" 2>/dev/null \
        | /usr/bin/grep -c 'R = 6')"

# --------------------------------------------------------------------------
section "128-bit needs --use-aes=y, and nothing else"
# --------------------------------------------------------------------------
# Without it qpdf writes RC4-128 and refuses the whole run with "refusing to
# write a file with RC4". The flag that would silence that refusal,
# --allow-weak-crypto, is deliberately NOT emitted here, so the two lines are
# load-bearing together and 20 lines apart in different branches.
reset_document
omc_control "$ENC_USER_PW_ID" "hunter2"
omc_control "$ENC_USER_PW_CONFIRM_ID" "hunter2"
omc_control "$ENC_BITS_ID" 128

check "128-bit asks for 128-bit keys"  "yes" "$(qpdf_has_arg encrypt --bits=128)"
check "and asks for AES explicitly"    "yes" "$(qpdf_has_arg encrypt --use-aes=y)"
check "without loosening the crypto policy" "no" \
    "$(qpdf_has_arg encrypt --allow-weak-crypto)"

_out="$OMCTEST_WORK/enc-128.pdf"
check "qpdf accepts the 128-bit arguments" "0" \
    "$(qpdf_run_built_args encrypt "$text_pdf" "$_out")"
check "and the result is AES-128" "1" \
    "$("$QPDF_BIN" --show-encryption --password=hunter2 "$_out" 2>/dev/null \
        | /usr/bin/grep -c 'R = 4')"

# The negative control for the pair above: the same request without --use-aes=y
# really is refused, so "we emit it" is a claim about something that matters.
check "the same request without --use-aes=y is refused" "2" \
    "$("$QPDF_BIN" --encrypt --user-password=hunter2 --owner-password=hunter2 \
        --bits=128 -- "$text_pdf" "$OMCTEST_WORK/enc-rc4.pdf" >/dev/null 2>&1; \
        printf '%s' "$?")"

# --------------------------------------------------------------------------
section "40-bit is the one strength that needs the override, and it goes first"
# --------------------------------------------------------------------------
# --allow-weak-crypto is a global flag. qpdf rejects it once --encrypt has
# opened its own argument block, so "somewhere in the list" is a weaker claim
# than the code needs: emitted in the wrong place, 40-bit encryption fails
# outright rather than degrading.
reset_document
omc_control "$ENC_USER_PW_ID" "hunter2"
omc_control "$ENC_USER_PW_CONFIRM_ID" "hunter2"
omc_control "$ENC_BITS_ID" 40

check "40-bit asks for 40-bit keys"       "yes" "$(qpdf_has_arg encrypt --bits=40)"
check "and carries the weak-crypto override" "yes" \
    "$(qpdf_has_arg encrypt --allow-weak-crypto)"
check "as the very first argument" "--allow-weak-crypto" "$(qpdf_arg_at encrypt 0)"

_out="$OMCTEST_WORK/enc-40.pdf"
check "qpdf accepts the 40-bit arguments" "0" \
    "$(qpdf_run_built_args encrypt "$text_pdf" "$_out")"
check "and the result is RC4-40" "1" \
    "$("$QPDF_BIN" --show-encryption --password=hunter2 "$_out" 2>/dev/null \
        | /usr/bin/grep -c 'R = 2')"

# --------------------------------------------------------------------------
section "an empty owner password is not an absent one"
# --------------------------------------------------------------------------
# Leaving it blank would write a document whose restrictions any reader can
# remove by opening it with no password at all, while the panel says the file is
# protected. The builder defaults it to the user password instead.
reset_document
omc_control "$ENC_USER_PW_ID" "hunter2"
omc_control "$ENC_USER_PW_CONFIRM_ID" "hunter2"
omc_control "$ENC_OWNER_PW_ID" ""
omc_control "$ENC_OWNER_PW_CONFIRM_ID" ""
check "the owner password falls back to the user password" "yes" \
    "$(qpdf_has_arg encrypt --owner-password=hunter2)"

# ...and a supplied one is used as given, or the fallback above would be
# indistinguishable from ignoring the field.
omc_control "$ENC_OWNER_PW_ID" "letmein"
omc_control "$ENC_OWNER_PW_CONFIRM_ID" "letmein"
check "a supplied owner password is used"   "yes" "$(qpdf_has_arg encrypt --owner-password=letmein)"
check "and does not become the user's"      "yes" "$(qpdf_has_arg encrypt --user-password=hunter2)"

# --------------------------------------------------------------------------
section "the optimize argument list"
# --------------------------------------------------------------------------
reset_document
# Object streams is a three-option picker, not a toggle, and its tag is
# interpolated straight into the flag. So the claim worth making is that every
# option the window offers survives the trip - a check that pinned only the
# default would stay green if the other two produced a flag qpdf rejects.
_unreached=""
for _tag in $(picker_tags "$OPT_OBJECT_STREAMS_ID"); do
    omc_control "$OPT_OBJECT_STREAMS_ID" "$_tag"
    if [ "$(qpdf_has_arg optimize "--object-streams=$_tag")" != yes ]; then
        _unreached="${_unreached:+$_unreached }$_tag"
    fi
done
check "every object-streams option reaches qpdf" "" "$_unreached"
# The loop is only meaningful if the picker really offered something; an empty
# option list would leave $_unreached empty too.
check "and the picker offered three of them" "3" \
    "$(picker_tags "$OPT_OBJECT_STREAMS_ID" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

# An untouched picker reports "" and has to mean the smallest option, not an
# empty flag. `--object-streams=` is a usage error, so getting this wrong breaks
# every Optimize run rather than degrading one.
omc_control "$OPT_OBJECT_STREAMS_ID" ""
check "an untouched picker still generates them" "yes" \
    "$(qpdf_has_arg optimize --object-streams=generate)"

reset_document
omc_control "$OPT_COMPRESS_STREAMS_ID" "false"
check "stream compression follows its own toggle" "no" \
    "$(qpdf_has_arg optimize --compress-streams=y)"

reset_document
omc_control "$OPT_RECOMPRESS_IMAGES_ID" "false"
check "recompression follows its own toggle" "0" \
    "$(quickpdf_eval 'build_qpdf_args optimize >/dev/null 2>&1; printf %s "$QPDF_RECOMPRESS_IMAGES"')"
check "and linearize is untouched by it" "1" \
    "$(quickpdf_eval 'build_qpdf_args optimize >/dev/null 2>&1; printf %s "$QPDF_LINEARIZE"')"

reset_document
omc_control "$OPT_LINEARIZE_ID" "false"
check "linearize follows its own toggle" "0" \
    "$(quickpdf_eval 'build_qpdf_args optimize >/dev/null 2>&1; printf %s "$QPDF_LINEARIZE"')"
check "and recompression is untouched by it" "1" \
    "$(quickpdf_eval 'build_qpdf_args optimize >/dev/null 2>&1; printf %s "$QPDF_RECOMPRESS_IMAGES"')"

# --------------------------------------------------------------------------
section "image_stage_helped decides whether the image stage earned its place"
# --------------------------------------------------------------------------
# Plain files, not PDFs: the predicate compares sizes and nothing else, and
# feeding it documents would make the assertions depend on how well a real
# engine happened to compress today.
_before="$OMCTEST_WORK/isz-before"
printf 'aaaaaaaaaaaaaaaa' > "$_before"
printf 'aaaa'                     > "$OMCTEST_WORK/isz-smaller"
printf 'aaaaaaaaaaaaaaaa'         > "$OMCTEST_WORK/isz-equal"
printf 'aaaaaaaaaaaaaaaaaaaaaaaa' > "$OMCTEST_WORK/isz-bigger"
: > "$OMCTEST_WORK/isz-empty"

stage_helped() { # <candidate>
    quickpdf_call image_stage_helped "$_before" "$1" && echo yes || echo no
}
check "a genuinely smaller result is kept" "yes" "$(stage_helped "$OMCTEST_WORK/isz-smaller")"
check "an equal-sized result is not"       "no"  "$(stage_helped "$OMCTEST_WORK/isz-equal")"
check "a larger result is not"             "no"  "$(stage_helped "$OMCTEST_WORK/isz-bigger")"
# mktemp pre-creates the output, so a run that produced nothing usable leaves a
# 0-byte file behind rather than no file. "Smaller than the input" would call
# that a perfect compression.
check "a 0-byte result is not a perfect compression" "no" \
    "$(stage_helped "$OMCTEST_WORK/isz-empty")"
check "a missing result is not"            "no"  "$(stage_helped "$OMCTEST_WORK/isz-nonexistent")"

# --------------------------------------------------------------------------
section "qpdf's own image optimizer is the fallback, and only the fallback"
# --------------------------------------------------------------------------
# pdfutil exiting 0 does not mean pdfutil helped: its Quartz filter re-encodes
# only the images it rescales, and current builds hand back the original bytes
# when their own result came out larger. optimize_file has to notice and let
# qpdf's weaker optimizer have a turn rather than passing untouched images to
# the structural pass.
#
# Which way it went is not visible in the output file - on the scans where
# pdfutil declines, qpdf often saves nothing either - so the observable is the
# argument list. Both engines are stubbed to make the decision deterministic.
_stubs="$OMCTEST_WORK/engine-stubs"
/bin/mkdir -p "$_stubs"

# A pdfutil that "succeeds" while returning the input unchanged.
cat > "$_stubs/pdfutil-noop" <<'STUB'
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

# ...and one that genuinely shrinks, so the fallback can be shown to stay off.
cat > "$_stubs/pdfutil-shrink" <<'STUB'
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
/usr/bin/truncate -s $(( $(/usr/bin/stat -f %z "$in") - 1 )) "$out"
STUB

# A qpdf that records its argument list and still produces a readable file.
cat > "$_stubs/qpdf-record" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" > "$QPDF_ARGS_LOG"
for a in "$@"; do last="$a"; done
cp "$QPDF_STUB_SOURCE" "$last"
STUB

/bin/chmod +x "$_stubs/pdfutil-noop" "$_stubs/pdfutil-shrink" "$_stubs/qpdf-record"
# A stub that is not executable never runs, and every assertion below then reads
# an argument log that was never written - an absent file, not a wrong one, so
# the negative checks would pass on emptiness.
_not_executable=""
for _stub in pdfutil-noop pdfutil-shrink qpdf-record; do
    [ -x "$_stubs/$_stub" ] || _not_executable="${_not_executable:+$_not_executable }$_stub"
done
check "every engine stub is executable" "" "$_not_executable"

export QPDF_ARGS_LOG="$OMCTEST_WORK/qpdf-args.log"
export QPDF_STUB_SOURCE="$text_pdf"

# Run optimize_file with both engines replaced, and report what qpdf was asked
# for. The library resolves QPDF and PDFUTIL from the bundle when it is sourced,
# so they are reassigned inside the same subshell, after the source and before
# the call.
optimize_with_stubs() { # <pdfutil-stub> <output>
    export OMCTEST_STUB_PDFUTIL="$1" OMCTEST_STUB_QPDF="$_stubs/qpdf-record"
    export OMCTEST_STUB_IN="$scan_pdf" OMCTEST_STUB_OUT="$2"
    : > "$QPDF_ARGS_LOG"
    quickpdf_eval '
        QPDF="$OMCTEST_STUB_QPDF"
        PDFUTIL="$OMCTEST_STUB_PDFUTIL"
        build_qpdf_args optimize >/dev/null 2>&1
        optimize_file "$OMCTEST_STUB_IN" "$OMCTEST_STUB_OUT" >/dev/null 2>&1' \
        >/dev/null 2>&1
    /bin/cat "$QPDF_ARGS_LOG" 2>/dev/null
}

reset_document
omc_control "$OPT_RECOMPRESS_IMAGES_ID" "true"
omc_control "$OPT_JPEG_QUALITY_ID" 60
omc_control "$OPT_LINEARIZE_ID" "false"
_args="$(optimize_with_stubs "$_stubs/pdfutil-noop" "$OMCTEST_WORK/fallback-on.pdf")"
check "the image stage ran at all"                "yes" "$(contains "$_args" "--compress-streams")"
check "a declining image stage hands over to qpdf" "yes" "$(contains "$_args" "--optimize-images")"
check "at the quality the panel asked for"        "yes" "$(contains "$_args" "--jpeg-quality=60")"

_args="$(optimize_with_stubs "$_stubs/pdfutil-shrink" "$OMCTEST_WORK/fallback-off.pdf")"
# Every negative below needs its own positive control, and this is not
# theoretical. The log is truncated before each run, so a scenario where the
# qpdf stub never ran at all leaves it EMPTY - and "the log does not contain
# --optimize-images" is then true for the wrong reason. A reviewer proved it:
# making a successful image stage skip the structural pass entirely, and
# dropping the qpdf stub from the chmod list, both left these checks green.
check "the structural pass still ran" "yes" "$(contains "$_args" "--compress-streams")"
check "an image stage that worked keeps qpdf out of it" "no" \
    "$(contains "$_args" "--optimize-images")"

# With the image stage switched off there is nothing to fall back from, so the
# flag must stay absent however the run goes.
reset_document
omc_control "$OPT_RECOMPRESS_IMAGES_ID" "false"
omc_control "$OPT_LINEARIZE_ID" "false"
_args="$(optimize_with_stubs "$_stubs/pdfutil-noop" "$OMCTEST_WORK/fallback-nostage.pdf")"
check "the structural pass ran with no image stage" "yes" \
    "$(contains "$_args" "--compress-streams")"
check "no image stage means no fallback" "no" "$(contains "$_args" "--optimize-images")"

unset QPDF_ARGS_LOG QPDF_STUB_SOURCE

# --------------------------------------------------------------------------
section "optimize_file, with the real engines"
# --------------------------------------------------------------------------
# The runner tests in 40-run drive this through a handler and a Save panel. What
# they cannot reach is the two-pass linearize decision and the failure path,
# because both are internal to optimize_file and leave no separate trace.
run_optimize() { # <input> <output> -> exit status
    export OMCTEST_OPT_IN="$1" OMCTEST_OPT_OUT="$2"
    quickpdf_eval '
        build_qpdf_args optimize >/dev/null 2>&1
        optimize_file "$OMCTEST_OPT_IN" "$OMCTEST_OPT_OUT" >/dev/null 2>&1
        printf "%s" "$?"'
}

# A non-PDF has to be reported as a fatal failure. Treated as success, the batch
# loop would count it as done and move the 0-byte staging file into place.
#
# The exact status matters and "not zero" is not good enough: the runners treat
# 3 as a COMPLETED run with warnings (QuickPDF.run.single.sh:67), so a pipeline
# that returned 3 here would be the very outcome this check exists to prevent
# while still passing a non-zero test. 2 is the fatal one.
reset_document
printf 'this is not a pdf\n' > "$OMCTEST_WORK/notapdf.pdf"
check "a non-PDF input fails the pipeline fatally" "2" \
    "$(run_optimize "$OMCTEST_WORK/notapdf.pdf" "$OMCTEST_WORK/opt-bad.pdf")"

# Linearize keep-if-smaller: the second pass is kept only when it did not grow
# the file, so either outcome is correct and the assertion is the invariant.
reset_document
omc_control "$OPT_RECOMPRESS_IMAGES_ID" "false"
omc_control "$OPT_LINEARIZE_ID" "false"
_plain="$OMCTEST_WORK/opt-plain.pdf"
_plain_rc="$(run_optimize "$text_pdf" "$_plain")"
check "the plain pass succeeded" "0" "$_plain_rc"

omc_control "$OPT_LINEARIZE_ID" "true"
_lin="$OMCTEST_WORK/opt-lin.pdf"
_lin_rc="$(run_optimize "$text_pdf" "$_lin")"
# 3 is qpdf reporting warnings on a file it still wrote, which a kept
# linearized pass can legitimately carry. Written as two [ ] tests rather than a
# case: a case pattern's ")" terminates the enclosing $( ), which is a parse
# error inside the substitution rather than a wrong answer.
check "the linearize pass succeeded or warned" "yes" \
    "$([ "$_lin_rc" = 0 ] || [ "$_lin_rc" = 3 ] && echo yes || echo no)"
check "and never delivered a larger file than the plain pass" "yes" \
    "$([ "$(/usr/bin/stat -f %z "$_lin")" -le "$(/usr/bin/stat -f %z "$_plain")" ] \
        && echo yes || echo no)"
check "the delivered file still has every page" "5" \
    "$("$QPDF_BIN" --show-npages "$_lin" 2>/dev/null)"
check "and its text survived" "yes" \
    "$(contains "$("$PDFUTIL_BIN" text "$_lin" 2>/dev/null)" "PAGE-3-MARKER")"

# --------------------------------------------------------------------------
section "what the pre-flight would have found"
# --------------------------------------------------------------------------
# 30-router proves the alert fires for a document with something to lose and
# stays quiet for one without. These are the answers underneath that decision,
# including the ones no fixture in the router file reaches.
check "a plain document has nothing at risk"   "" "$(quickpdf_call pdf_structure_at_risk "$text_pdf")"
check "a scan has nothing at risk"             "" "$(quickpdf_call pdf_structure_at_risk "$scan_pdf")"
check "an outline is at risk"            "outline" "$(quickpdf_call pdf_structure_at_risk "$outlined_pdf")"
check "form fields are reported as annotations" "annotations" \
    "$(quickpdf_call pdf_structure_at_risk "$formfilled_pdf")"

# A guard must not block work over a question it could not answer, so anything
# unreadable reads as "nothing at risk" rather than as "everything at risk".
printf 'not a pdf at all\n' > "$OMCTEST_WORK/notes.txt"
check "a non-PDF is not reported as at risk" "" \
    "$(quickpdf_call pdf_structure_at_risk "$OMCTEST_WORK/notes.txt")"
check "a missing file is not reported as at risk" "" \
    "$(quickpdf_call pdf_structure_at_risk "$OMCTEST_WORK/does-not-exist.pdf")"

# Both at once. Stamping an annotation onto the outlined fixture is the only way
# to reach the combined string through the real parser rather than by handing
# structure_risk_phrase a string this suite wrote itself.
_both="$OMCTEST_WORK/both.pdf"
"$PDFUTIL_BIN" watermark --text "draft" --annotation --force -o "$_both" "$outlined_pdf" \
    >/dev/null 2>&1
check "the combined fixture was built" "yes" \
    "$([ -s "$_both" ] && echo yes || echo no)"
check "a document with both is reported as both" "outline annotations" \
    "$(quickpdf_call pdf_structure_at_risk "$_both")"

# The phrases complete the sentence "<FILE> has ...", so each one is checked as
# the user reads it rather than for a substring.
check "phrase: an outline"     "an outline" "$(quickpdf_call structure_risk_phrase "outline")"
check "phrase: annotations"    "annotations or form fields" \
    "$(quickpdf_call structure_risk_phrase "annotations")"
check "phrase: both"           "an outline and annotations or form fields" \
    "$(quickpdf_call structure_risk_phrase "outline annotations")"
# The caller only reaches the phrase when something WAS found, so the catch-all
# exists to keep an unexpected value from rendering as "report.pdf has ."
check "phrase: an unmapped finding still completes the sentence" \
    "structure that will not survive" \
    "$(quickpdf_call structure_risk_phrase "something new")"

# --------------------------------------------------------------------------
section "only Optimize redraws, and only with recompression on"
# --------------------------------------------------------------------------
redraws() { # -> yes | no
    quickpdf_call optimize_redraws && echo yes || echo no
}

reset_document
omc_control "$OPERATION_PICKER_ID" optimize
omc_control "$OPT_RECOMPRESS_IMAGES_ID" "true"
check "optimize with recompression on redraws" "yes" "$(redraws)"
omc_control "$OPT_RECOMPRESS_IMAGES_ID" "false"
check "and with it off, does not"              "no"  "$(redraws)"

# An untouched picker reports "" and means optimize. This is a different code
# path from the declared default - current_operation's own fallback - and the
# window never shows it, so nothing else exercises it.
omc_control "$OPERATION_PICKER_ID" ""
omc_control "$OPT_RECOMPRESS_IMAGES_ID" "true"
check "an untouched operation picker still means optimize" "yes" "$(redraws)"

# No other operation redraws, whatever the image toggle happens to hold. Some of
# them still remove things - Flatten takes out form fields - but that is the
# operation doing what was asked, which is not what this guard is about.
# 30-router checks one of these through the handler; the rest are only here.
_wrongly_warns=""
for _op in encrypt decrypt rotate extract split merge repair metadata flatten; do
    omc_control "$OPERATION_PICKER_ID" "$_op"
    if [ "$(redraws)" = "yes" ]; then
        _wrongly_warns="${_wrongly_warns:+$_wrongly_warns }$_op"
    fi
done
check "no other operation warns about redrawing" "" "$_wrongly_warns"

# The positive control for the loop above. An empty result there means either
# "nine operations were asked and none warned" or "the loop never ran and the
# variable was never touched", and those are not the same answer. Running the
# identical body over a list that DOES contain a redrawing operation has to
# name it.
_control_warns=""
for _op in encrypt optimize flatten; do
    omc_control "$OPERATION_PICKER_ID" "$_op"
    if [ "$(redraws)" = "yes" ]; then
        _control_warns="${_control_warns:+$_control_warns }$_op"
    fi
done
check "and the loop that says so can still see one" "optimize" "$_control_warns"

omctest_end
