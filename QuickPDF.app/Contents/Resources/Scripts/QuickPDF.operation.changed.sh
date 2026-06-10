#!/bin/bash
# QuickPDF.operation.changed.sh - Swap the visible settings panel

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

operation="$OMC_ACTIONUI_VIEW_60_VALUE"
[ -z "$operation" ] && operation="optimize"

show_group() {
    local visible_id="$1"
    local gid
    for gid in ${GROUP_OPTIMIZE_ID} ${GROUP_ENCRYPT_ID} ${GROUP_DECRYPT_ID} \
               ${GROUP_INSPECT_ID} ${GROUP_ROTATE_ID} ${GROUP_EXTRACT_ID} \
               ${GROUP_SPLIT_ID} ${GROUP_MERGE_ID} ${GROUP_REPAIR_ID} \
               ${GROUP_METADATA_ID} ${GROUP_FLATTEN_ID}; do
        if [ "$gid" = "$visible_id" ]; then
            "$dialog_tool" "$window_uuid" "$gid" omc_show
        else
            "$dialog_tool" "$window_uuid" "$gid" omc_hide
        fi
    done
}

case "$operation" in
    optimize) show_group ${GROUP_OPTIMIZE_ID} ;;
    encrypt)  show_group ${GROUP_ENCRYPT_ID} ;;
    decrypt)  show_group ${GROUP_DECRYPT_ID} ;;
    rotate)   show_group ${GROUP_ROTATE_ID} ;;
    extract)  show_group ${GROUP_EXTRACT_ID} ;;
    split)    show_group ${GROUP_SPLIT_ID} ;;
    merge)    show_group ${GROUP_MERGE_ID} ;;
    repair)   show_group ${GROUP_REPAIR_ID} ;;
    metadata) show_group ${GROUP_METADATA_ID} ;;
    flatten)  show_group ${GROUP_FLATTEN_ID} ;;
    inspect)  show_group ${GROUP_INSPECT_ID} ;;
esac

# The overwrite toggle only applies to operations that write into a chosen
# destination folder. Inspect writes nothing; Merge's save panel asks itself.
case "$operation" in
    inspect|merge)
        "$dialog_tool" "$window_uuid" ${OVERWRITE_TOGGLE_ID} omc_disable
        ;;
    *)
        "$dialog_tool" "$window_uuid" ${OVERWRITE_TOGGLE_ID} omc_enable
        ;;
esac
