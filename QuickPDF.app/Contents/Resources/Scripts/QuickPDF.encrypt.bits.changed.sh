#!/bin/bash
# QuickPDF.encrypt.bits.changed.sh - Explain the cost of leaving the default
#
# The default (256-bit AES) needs no notice: it is the strongest option, and
# current readers accept it. Each of the other two trades something away, in
# different directions, so the notice text is per-option rather than a single
# "weak encryption" line.
#
# 128-bit's notice is about the password, not the key. The obvious warning to
# write there would be about old readers, but that is the reason somebody would
# CHOOSE it; the thing they cannot see is that it stores only the first 32
# characters of what they typed - measured, not assumed, and the reason 256 is
# the default. See the ENC_DEFAULT_BITS comment in lib.QuickPDF.sh.
#
# The text is set with the plain value form rather than
# omc_set_property "text" - the property form is accepted but does not repaint
# a Text element.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

bits="$OMC_ACTIONUI_VIEW_112_VALUE"
[ -z "$bits" ] && bits=$ENC_DEFAULT_BITS

case "$bits" in
    128)
        notice="128-bit AES stores only the first 32 characters of the password. Choose it when a reader is too old for 256-bit AES."
        ;;
    40)
        notice="40-bit RC4 is easily broken by freely available tools. Stores only the first 32 characters of the password. Use it only for very old readers."
        ;;
    *)
        notice=""
        ;;
esac

if [ -z "$notice" ]; then
    # Cleared as well as hidden. ActionUI's "hidden" maps to SwiftUI .hidden(),
    # which still RESERVES the element's layout space, and the element keeps
    # whatever value was last written to it - so hiding the three-line 40-bit
    # notice without clearing it leaves a three-line invisible gap under the
    # picker, and everything below shifts according to which options the user
    # happened to browse through.
    "$dialog_tool" "$window_uuid" ${ENC_STRENGTH_NOTICE_ID} ""
    "$dialog_tool" "$window_uuid" ${ENC_STRENGTH_NOTICE_ID} omc_set_property "hidden" "true"
else
    "$dialog_tool" "$window_uuid" ${ENC_STRENGTH_NOTICE_ID} "$notice"
    "$dialog_tool" "$window_uuid" ${ENC_STRENGTH_NOTICE_ID} omc_set_property "hidden" "false"
fi
