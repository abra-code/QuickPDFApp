#!/bin/bash
# QuickPDF.encrypt.bits.changed.sh - Warn when a weak key length is selected

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

bits="$OMC_ACTIONUI_VIEW_112_VALUE"

if [ "$bits" = "256" ] || [ -z "$bits" ]; then
    "$dialog_tool" "$window_uuid" ${ENC_WEAK_WARNING_ID} omc_set_property "hidden" "true"
else
    "$dialog_tool" "$window_uuid" ${ENC_WEAK_WARNING_ID} omc_set_property "hidden" "false"
fi
