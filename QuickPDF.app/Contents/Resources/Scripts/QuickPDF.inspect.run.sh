#!/bin/bash
# QuickPDF.inspect.run.sh - Read-only inspection, results in the output window

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

file_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_2_ALL_ROWS"
if [ -z "$file_paths" ]; then
    echo "No files to inspect."
    exit 0
fi

mode="$OMC_ACTIONUI_VIEW_170_VALUE"
[ -z "$mode" ] && mode="check"

IFS=$'\n' read -r -d '' -a files <<< "$file_paths" || true

for file_path in "${files[@]}"; do
    [ -z "$file_path" ] && continue

    echo "================================================================"
    echo "$file_path"
    echo "================================================================"

    if [ ! -e "$file_path" ]; then
        echo "File does not exist."
        echo ""
        continue
    fi

    case "$mode" in
        check)
            "$QPDF" --check "$file_path" 2>&1
            ;;
        pages)
            npages="$("$QPDF" --show-npages "$file_path" 2>&1)"
            echo "Pages: $npages"
            ;;
        encryption)
            "$QPDF" --show-encryption "$file_path" 2>&1
            ;;
        json)
            "$QPDF" --json "$file_path" 2>&1
            ;;
    esac
    echo ""
done
