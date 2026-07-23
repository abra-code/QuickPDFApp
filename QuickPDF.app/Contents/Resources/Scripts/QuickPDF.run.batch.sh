#!/bin/bash
# QuickPDF.run.batch.sh - Apply the chosen operation to every file in the list
#
# Reached via QuickPDF.start.batch. CHOOSE_FOLDER_DIALOG has already asked
# for the destination folder (OMC_DLG_CHOOSE_FOLDER_PATH).

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

destination="$OMC_DLG_CHOOSE_FOLDER_PATH"
if [ -z "$destination" ]; then
    exit 0
fi

file_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_2_ALL_ROWS"
if [ -z "$file_paths" ]; then
    exit 0
fi

operation="$OMC_ACTIONUI_VIEW_60_VALUE"
[ -z "$operation" ] && operation="optimize"

# Fill QPDF_ARGS / QPDF_POST_ARGS / QPDF_LINEARIZE from the UI
build_qpdf_args "$operation"

IFS=$'\n' read -r -d '' -a files <<< "$file_paths" || true

success_count=0
warn_count=0
error_count=0
renamed_count=0
details=""

# run_qpdf and optimize_file are provided by lib.QuickPDF.sh

set_summary "Running ${operation} on ${#files[@]} file(s)…"

for file_path in "${files[@]}"; do
    [ -z "$file_path" ] && continue

    filename="$(/usr/bin/basename "$file_path")"

    if [ ! -e "$file_path" ]; then
        error_count=$((error_count + 1))
        details="${details}
✗ ${filename}: file does not exist"
        continue
    fi

    # Split is 1:N - parts go into a destination subfolder named after the file
    if [ "$operation" = "split" ]; then
        name_no_ext="${filename%.*}"
        # Never overwrite: pick a fresh folder name if one already exists
        subdir="$(unique_path "$destination/$name_no_ext")"
        subdir_name="$(/usr/bin/basename "$subdir")"
        rename_note=""
        if [ "$subdir_name" != "$name_no_ext" ]; then
            renamed_count=$((renamed_count + 1))
            rename_note=" — renamed, ${name_no_ext}/ already existed"
        fi

        /bin/mkdir -p "$subdir"
        # qpdf inserts the page-group number before the .pdf extension
        output="$("$QPDF" "${QPDF_ARGS[@]}" "$file_path" "$subdir/${name_no_ext}.pdf" 2>&1)"
        exit_code=$?

        if [ $exit_code -eq 0 ] || [ $exit_code -eq 3 ]; then
            part_count="$(/bin/ls "$subdir" 2>/dev/null | /usr/bin/grep -c '\.pdf$')"
            if [ $exit_code -eq 3 ]; then
                warn_count=$((warn_count + 1))
                details="${details}
⚠ ${filename}: split into ${part_count} part(s) → ${subdir_name}/ (with warnings)${rename_note}"
            else
                success_count=$((success_count + 1))
                details="${details}
✓ ${filename}: split into ${part_count} part(s) → ${subdir_name}/${rename_note}"
            fi
        else
            error_count=$((error_count + 1))
            err_line="$(printf '%s' "$output" | /usr/bin/head -1 | /usr/bin/sed 's/^qpdf: //')"
            details="${details}
✗ ${filename}: ${err_line:-failed (exit $exit_code)}"
        fi
        continue
    fi

    # Never overwrite: pick a fresh file name if one already exists
    output_file="$(unique_path "$destination/$filename")"
    output_name="$(/usr/bin/basename "$output_file")"
    rename_note=""
    if [ "$output_name" != "$filename" ]; then
        renamed_count=$((renamed_count + 1))
        rename_note=" — saved as ${output_name}, file already existed"
    fi

    # qpdf refuses identical input and output paths - always write to a temp
    # file in the destination folder, then move into place.
    tmp_out="$(/usr/bin/mktemp "$destination/.quickpdf.XXXXXX")"

    if [ "$operation" = "optimize" ]; then
        # Optional pdfutil reduce image stage, then qpdf structural pass with the
        # linearize keep-if-smaller two-pass (see optimize_file in lib).
        output="$(optimize_file "$file_path" "$tmp_out")"
        exit_code=$?
    else
        output="$(run_qpdf "$file_path" "$tmp_out")"
        exit_code=$?
    fi

    if [ $exit_code -eq 0 ] || [ $exit_code -eq 3 ]; then
        # mktemp creates 0600 files - give the result normal permissions
        /bin/chmod 644 "$tmp_out"
        /bin/mv -f "$tmp_out" "$output_file"
        orig_size="$(/usr/bin/stat -f %z "$file_path")"
        new_size="$(/usr/bin/stat -f %z "$output_file")"
        if [ $exit_code -eq 3 ]; then
            warn_count=$((warn_count + 1))
            details="${details}
⚠ ${filename}: $(format_size "$orig_size") → $(format_size "$new_size") (with warnings)${rename_note}"
        else
            success_count=$((success_count + 1))
            details="${details}
✓ ${filename}: $(format_size "$orig_size") → $(format_size "$new_size")${rename_note}"
        fi
    else
        /bin/rm -f "$tmp_out"
        error_count=$((error_count + 1))
        # First line of qpdf's message, without the leading "qpdf: " prefix
        err_line="$(printf '%s' "$output" | /usr/bin/head -1 | /usr/bin/sed 's/^qpdf: //')"
        details="${details}
✗ ${filename}: ${err_line:-failed (exit $exit_code)}"
    fi
done

summary="Operation: ${operation}
Destination: ${destination}

${success_count} succeeded · ${warn_count} with warnings · ${renamed_count} renamed · ${error_count} failed
${details}"

set_summary "$summary"
