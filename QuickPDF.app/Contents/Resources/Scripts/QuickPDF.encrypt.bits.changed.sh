#!/bin/bash
# QuickPDF.encrypt.bits.changed.sh - Explain the cost of leaving the default
#
# The default (128-bit AES) needs no notice: it is the setting every reader
# still in service accepts. The other two options each trade something away,
# in opposite directions, so the notice text is per-option rather than a
# single "weak encryption" line.
#
# The text is set with the plain value form rather than
# omc_set_property "text" - the property form is accepted but does not repaint
# a Text element.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

bits="$OMC_ACTIONUI_VIEW_112_VALUE"
[ -z "$bits" ] && bits=$ENC_DEFAULT_BITS

case "$bits" in
    256)
        notice="256-bit AES is stronger, but older readers may refuse it."
        ;;
    40)
        notice="40-bit RC4 is obsolete and broken in seconds by freely available tools. Use it only when a very old reader leaves no choice."
        ;;
    *)
        notice=""
        ;;
esac

if [ -z "$notice" ]; then
    "$dialog_tool" "$window_uuid" ${ENC_STRENGTH_NOTICE_ID} omc_set_property "hidden" "true"
else
    "$dialog_tool" "$window_uuid" ${ENC_STRENGTH_NOTICE_ID} "$notice"
    "$dialog_tool" "$window_uuid" ${ENC_STRENGTH_NOTICE_ID} omc_set_property "hidden" "false"
fi
