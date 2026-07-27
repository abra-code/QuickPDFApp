# Set Password argument construction - the command line the APP actually builds.
#
# encryption-interop.sh drives qpdf directly, with the legacy positional form
# (`--encrypt secret owner 128`). That is a different argument list from the one
# build_qpdf_args assembles, so it cannot catch a regression in the app's own
# flag logic - the suite would stay green with the app hopelessly broken.
#
# These cases source lib.QuickPDF.sh and drive build_qpdf_args with stubbed
# control values, exactly as a handler script would, then run the result.

enc_args() {
    # enc_args <picker value> -> sets QPDF_ARGS for a plain user-password encrypt
    QPDF_ARGS=()
    QPDF_POST_ARGS=()
    OMC_ACTIONUI_VIEW_110_VALUE="hunter2"
    OMC_ACTIONUI_VIEW_111_VALUE=""
    OMC_ACTIONUI_VIEW_112_VALUE="$1"
    OMC_ACTIONUI_VIEW_113_VALUE="true"
    OMC_ACTIONUI_VIEW_114_VALUE=""
    OMC_ACTIONUI_VIEW_115_VALUE="true"
    OMC_ACTIONUI_VIEW_116_VALUE=""
    export OMC_ACTIONUI_VIEW_110_VALUE OMC_ACTIONUI_VIEW_111_VALUE \
           OMC_ACTIONUI_VIEW_112_VALUE OMC_ACTIONUI_VIEW_113_VALUE \
           OMC_ACTIONUI_VIEW_114_VALUE OMC_ACTIONUI_VIEW_115_VALUE \
           OMC_ACTIONUI_VIEW_116_VALUE
    build_qpdf_args encrypt
}

args_contain() {
    printf '%s\n' "${QPDF_ARGS[@]}" | grep -qx -- "$1"
}
expect_arg() {
    if ! args_contain "$1"; then
        fail "expected argument [$1] in: ${QPDF_ARGS[*]}"
    fi
}
expect_no_arg() {
    if args_contain "$1"; then
        fail "unexpected argument [$1] in: ${QPDF_ARGS[*]}"
    fi
}

(
    # Subshell: sourcing the lib defines control-ID constants and helper
    # functions that the other case files have no reason to inherit.
    OMC_APP_BUNDLE_PATH="$APP"
    OMC_OMC_SUPPORT_PATH="/nonexistent"
    export OMC_APP_BUNDLE_PATH OMC_OMC_SUPPORT_PATH
    . "$LIB"

    # --- the default, i.e. the picker never touched --------------------------
    #
    # The Encryption Strength picker declares no value, so ActionUI selects its
    # first option and an untouched picker reports "". Both must mean 128.
    for picker in "" "128"; do
        enc_args "$picker"
        expect_arg "--bits=128"
        expect_arg "--use-aes=y"

        # --use-aes=y is load-bearing, not cosmetic: 128-bit without it is
        # RC4-128, which qpdf refuses unless --allow-weak-crypto is also passed
        # - and that flag is deliberately scoped to 40-bit now. Delete either
        # line in lib.QuickPDF.sh and this case fails.
        expect_no_arg "--allow-weak-crypto"

        out="$TMP/args-default-${picker:-empty}.pdf"
        expect_ok "$QPDF" "${QPDF_ARGS[@]}" "$FIX/text.pdf" "$out"
        expect_grep "R = 4" "$QPDF" --show-encryption --password=hunter2 "$out"
    done

    # Proof the assertion above is not vacuous: the same call without
    # --use-aes=y really is rejected, so the flag is what makes 128 work.
    expect_code 2 "$QPDF" --encrypt --user-password=hunter2 \
        --owner-password=hunter2 --bits=128 -- "$FIX/text.pdf" "$TMP/args-rc4.pdf"

    # --- 256-bit -------------------------------------------------------------
    enc_args 256
    expect_arg "--bits=256"
    expect_no_arg "--use-aes=y"
    expect_no_arg "--allow-weak-crypto"
    expect_ok "$QPDF" "${QPDF_ARGS[@]}" "$FIX/text.pdf" "$TMP/args-256.pdf"
    expect_grep "R = 6" "$QPDF" --show-encryption --password=hunter2 "$TMP/args-256.pdf"

    # --- 40-bit is the only strength that still needs the override -----------
    enc_args 40
    expect_arg "--allow-weak-crypto"
    expect_arg "--bits=40"
    # The flag is global and qpdf rejects it inside the --encrypt block, so its
    # position matters as much as its presence.
    expect_eq "--allow-weak-crypto" "${QPDF_ARGS[0]}" "weak-crypto flag position"
    expect_ok "$QPDF" "${QPDF_ARGS[@]}" "$FIX/text.pdf" "$TMP/args-40.pdf"
    expect_grep "R = 2" "$QPDF" --show-encryption --password=hunter2 "$TMP/args-40.pdf"

    # --- an empty owner password must not leave restrictions removable -------
    enc_args ""
    expect_arg "--owner-password=hunter2"
)
