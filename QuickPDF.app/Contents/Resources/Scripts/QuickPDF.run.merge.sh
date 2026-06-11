#!/bin/bash
# QuickPDF.run.merge.sh - Combine all listed files into one PDF (N:1)
#
# Reached via QuickPDF.start.batch. SAVE_AS_DIALOG has already asked for the
# output file (OMC_DLG_SAVE_AS_PATH); the save panel handles replace prompts.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

output_file="$OMC_DLG_SAVE_AS_PATH"
if [ -z "$output_file" ]; then
    exit 0
fi

# If we append .pdf ourselves, the save panel never confirmed that final
# path - never overwrite, pick a unique name instead.
case "$output_file" in
    *.pdf|*.PDF) ;;
    *)
        output_file="$(unique_path "${output_file}.pdf")"
        ;;
esac

file_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_2_ALL_ROWS"
if [ -z "$file_paths" ]; then
    exit 0
fi

IFS=$'\n' read -r -d '' -a files <<< "$file_paths" || true

# Optional page range applied to every input file (qpdf --pages syntax:
# "file range file range ...", default range when omitted is all pages)
range="$OMC_ACTIONUI_VIEW_141_VALUE"

pages_args=()
for file_path in "${files[@]}"; do
    [ -z "$file_path" ] && continue
    if [ ! -e "$file_path" ]; then
        set_summary "Merge aborted: file does not exist:
$file_path"
        exit 0
    fi
    pages_args+=("$file_path")
    [ -n "$range" ] && pages_args+=("$range")
done

set_summary "Merging ${#files[@]} files…"

# The chosen output may be one of the inputs - write to a temp file in the
# same folder, then move into place.
out_dir="$(/usr/bin/dirname "$output_file")"
tmp_out="$(/usr/bin/mktemp "$out_dir/.quickpdf.XXXXXX")"

output="$("$QPDF" --empty --pages "${pages_args[@]}" -- "$tmp_out" 2>&1)"
exit_code=$?

if [ $exit_code -eq 0 ] || [ $exit_code -eq 3 ]; then
    /bin/chmod 644 "$tmp_out"
    /bin/mv -f "$tmp_out" "$output_file"
    new_size="$(/usr/bin/stat -f %z "$output_file")"
    pages="$("$QPDF" --show-npages "$output_file" 2>/dev/null)"
    warn_note=""
    [ $exit_code -eq 3 ] && warn_note="
⚠ qpdf reported warnings:
$output"
    set_summary "✓ Merged ${#files[@]} files → $output_file
Pages: ${pages:-?} · Size: $(format_size "$new_size")${warn_note}"
else
    /bin/rm -f "$tmp_out"
    set_summary "✗ Merge failed:
$output"
fi
