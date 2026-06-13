#!/bin/bash
# QuickPDF.run.single.sh - Process exactly one PDF file to one output file (1:1 mode)
#
# Reached via QuickPDF.start.batch when the list contains a single file
# and the operation is a 1-in/1-out transform (optimize, encrypt, decrypt,
# rotate, repair, metadata, flatten).
#
# SAVE_AS_DIALOG has already asked for the exact output file path
# (OMC_DLG_SAVE_AS_PATH). Split and Extract Pages still use folder selection
# even for a single input (they can produce multiple outputs).

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.QuickPDF.sh"

# env | sort

output_file="$OMC_DLG_SAVE_AS_PATH"
if [ -z "$output_file" ]; then
    exit 0
fi

# Ensure we have a .pdf extension. If the user typed a name without one in the
# save panel, append .pdf. If that final name wasn't confirmed by the panel,
# pick a unique name to avoid silent overwrite.
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

# We should only have one file in single mode, but take the first safely.
input_file=$(printf '%s\n' "$file_paths" | /usr/bin/head -1 | /usr/bin/tr -d '\r')
if [ -z "$input_file" ] || [ ! -e "$input_file" ]; then
    set_summary "Single-file operation aborted: input file does not exist."
    exit 0
fi

filename="$(/usr/bin/basename "$input_file")"
operation="$OMC_ACTIONUI_VIEW_60_VALUE"
[ -z "$operation" ] && operation="optimize"

# Fill QPDF_ARGS / QPDF_POST_ARGS / QPDF_LINEARIZE from the UI
build_qpdf_args "$operation"

set_summary "Running ${operation} on ${filename}…"

# qpdf refuses to write when input path == output path.
# Always stage through a temp file in the destination directory, then mv.
out_dir="$(/usr/bin/dirname "$output_file")"
tmp_out="$(/usr/bin/mktemp "$out_dir/.quickpdf.XXXXXX")"

# Local helper (same as in run.batch.sh)
run_qpdf() {
    "$QPDF" "${QPDF_ARGS[@]}" "$1" "${QPDF_POST_ARGS[@]}" "$2" 2>&1
}

if [ "$operation" = "optimize" ] && [ "$QPDF_LINEARIZE" = "1" ]; then
    # Two-pass linearize: only keep the linearized version if it is smaller
    output="$(run_qpdf "$input_file" "$tmp_out")"
    exit_code=$?
    if [ $exit_code -ne 2 ]; then
        tmp_linear="$(/usr/bin/mktemp "$out_dir/.quickpdf.XXXXXX")"
        QPDF_ARGS+=(--linearize)
        lin_output="$(run_qpdf "$input_file" "$tmp_linear")"
        lin_exit=$?
        # Restore args for potential future use (defensive)
        unset 'QPDF_ARGS[${#QPDF_ARGS[@]}-1]'
        if [ $lin_exit -ne 2 ]; then
            plain_size="$(/usr/bin/stat -f %z "$tmp_out")"
            linear_size="$(/usr/bin/stat -f %z "$tmp_linear")"
            if [ "$linear_size" -le "$plain_size" ]; then
                /bin/mv -f "$tmp_linear" "$tmp_out"
            else
                /bin/rm -f "$tmp_linear"
            fi
        else
            /bin/rm -f "$tmp_linear"
        fi
    fi
else
    output="$(run_qpdf "$input_file" "$tmp_out")"
    exit_code=$?
fi

if [ $exit_code -eq 0 ] || [ $exit_code -eq 3 ]; then
    /bin/chmod 644 "$tmp_out"
    /bin/mv -f "$tmp_out" "$output_file"

    orig_size="$(/usr/bin/stat -f %z "$input_file")"
    new_size="$(/usr/bin/stat -f %z "$output_file")"

    if [ $exit_code -eq 3 ]; then
        warn_note="
⚠ qpdf reported warnings:
$output"
        set_summary "✓ ${filename}: $(format_size "$orig_size") → $(format_size "$new_size") (with warnings)
Output: $output_file${warn_note}"
    else
        set_summary "✓ ${filename}: $(format_size "$orig_size") → $(format_size "$new_size")
Output: $output_file"
    fi
else
    /bin/rm -f "$tmp_out"
    err_line="$(printf '%s' "$output" | /usr/bin/head -1 | /usr/bin/sed 's/^qpdf: //')"
    set_summary "✗ ${filename}: ${err_line:-failed (exit $exit_code)}"
fi
