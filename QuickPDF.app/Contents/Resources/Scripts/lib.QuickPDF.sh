#!/bin/bash
# lib.QuickPDF.sh - Shared functions and variables for QuickPDF

# Embedded qpdf binary
QPDF="$OMC_APP_BUNDLE_PATH/Contents/Helpers/qpdf"

# Control IDs
TABLE_ID=10
SUMMARY_VIEW_ID=12
OVERWRITE_TOGGLE_ID=14
REMOVE_BUTTON_ID=102
REVEAL_BUTTON_ID=104
INFO_BUTTON_ID=106

OPERATION_PICKER_ID=60

# Optimize controls
OPT_LINEARIZE_ID=70
OPT_COMPRESS_STREAMS_ID=71
OPT_RECOMPRESS_IMAGES_ID=72
OPT_JPEG_QUALITY_ID=73
OPT_OBJECT_STREAMS_ID=74
OPT_REMOVE_UNREF_ID=75

# Encrypt controls
ENC_USER_PW_ID=110
ENC_OWNER_PW_ID=111
ENC_BITS_ID=112
ENC_ALLOW_PRINT_ID=113
ENC_ALLOW_MODIFY_ID=114
ENC_ALLOW_EXTRACT_ID=115
ENC_ALLOW_ANNOTATE_ID=116
ENC_WEAK_WARNING_ID=118

# Decrypt controls
DEC_PASSWORD_ID=120
DEC_RESTRICTIONS_ONLY_ID=121

# Inspect controls
INSPECT_MODE_PICKER_ID=170

# Operation GroupBox IDs (ZStack panel switcher)
GROUP_OPTIMIZE_ID=200
GROUP_ENCRYPT_ID=210
GROUP_DECRYPT_ID=220
GROUP_INSPECT_ID=230

RUN_BUTTON_ID=90

# Runtime tools
dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
next_cmd="$OMC_OMC_SUPPORT_PATH/omc_next_command"
alert_tool="$OMC_OMC_SUPPORT_PATH/alert"
window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

# Set the Summary text view content
# Arguments: text
set_summary() {
    "$dialog_tool" "$window_uuid" ${SUMMARY_VIEW_ID} "$1"
}

# Check whether a path looks like a PDF file (extension, case-insensitive)
# Arguments: path
is_pdf_file() {
    case "$1" in
        *.pdf|*.PDF|*.Pdf|*.pDF|*.pdF|*.PDf|*.pDf|*.PdF) return 0 ;;
        *) return 1 ;;
    esac
}

# Add PDF files to the table, keeping existing rows, deduped and sorted.
# Directories are searched recursively for *.pdf.
# Arguments: newline-separated list of file/directory paths to add
add_files_to_table() {
    local new_paths="$1"
    local buffer=""

    # Keep existing rows
    local existing_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_2_ALL_ROWS"
    if [ -n "$existing_paths" ]; then
        while IFS= read -r file_path; do
            if [ -n "$file_path" ]; then
                local filename="$(/usr/bin/basename "$file_path")"
                buffer="${buffer}${filename}	${file_path}
"
            fi
        done <<< "$existing_paths"
    fi

    # Add new files / folders (filtered to PDFs)
    while IFS= read -r file_path; do
        if [ -d "$file_path" ]; then
            local tmp_files="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/quickpdf.XXXXXX")"
            /usr/bin/find "$file_path" -type f ! -path "*/.*" -iname "*.pdf" -print > "$tmp_files" 2>/dev/null
            while IFS= read -r found_file; do
                local filename="$(/usr/bin/basename "$found_file")"
                buffer="${buffer}${filename}	${found_file}
"
            done < "$tmp_files"
            /bin/rm -f "$tmp_files"
        elif [ -e "$file_path" ] && is_pdf_file "$file_path"; then
            local filename="$(/usr/bin/basename "$file_path")"
            buffer="${buffer}${filename}	${file_path}
"
        fi
    done <<< "$new_paths"

    if [ -n "$buffer" ]; then
        printf "%s" "$buffer" | /usr/bin/sort -u | "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_set_rows_from_stdin
    else
        "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_remove_all_rows
    fi
}

# Human-readable file size
# Arguments: byte count
format_size() {
    local bytes="$1"
    if [ -z "$bytes" ]; then
        echo "?"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$(( bytes / 1048576 )).$(( (bytes % 1048576) * 10 / 1048576 )) MB"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$(( bytes / 1024 )) KB"
    else
        echo "${bytes} bytes"
    fi
}

# Validate a 1-100 integer; echoes the clamped value (default on garbage)
# Arguments: value default
clamp_quality() {
    local q="$1" def="$2"
    case "$q" in
        '' | *[!0-9]*) q="$def" ;;
        *)
            [ "$q" -gt 100 ] && q=100
            [ "$q" -lt 1 ] && q=1
            ;;
    esac
    echo "$q"
}

# Build the qpdf argument list for the current operation into the global
# array QPDF_ARGS (flags only — no input/output paths).
# For "optimize", the linearize toggle is reported separately in
# QPDF_LINEARIZE (1/0) so the batch loop can do the two-pass size check.
# Arguments: operation tag (optimize|encrypt|decrypt)
build_qpdf_args() {
    local op="$1"
    QPDF_ARGS=()
    QPDF_LINEARIZE=0

    case "$op" in
        optimize)
            if [ "$OMC_ACTIONUI_VIEW_71_VALUE" = "true" ]; then
                QPDF_ARGS+=(--compress-streams=y --recompress-flate --compression-level=9)
            fi
            local obj_streams="$OMC_ACTIONUI_VIEW_74_VALUE"
            [ -z "$obj_streams" ] && obj_streams="generate"
            QPDF_ARGS+=("--object-streams=$obj_streams")
            if [ "$OMC_ACTIONUI_VIEW_75_VALUE" = "true" ]; then
                QPDF_ARGS+=(--remove-unreferenced-resources=yes)
            fi
            if [ "$OMC_ACTIONUI_VIEW_72_VALUE" = "true" ]; then
                local quality=$(clamp_quality "$OMC_ACTIONUI_VIEW_73_VALUE" 85)
                QPDF_ARGS+=(--optimize-images "--jpeg-quality=$quality" --oi-min-width=64 --oi-min-height=64)
            fi
            if [ "$OMC_ACTIONUI_VIEW_70_VALUE" = "true" ]; then
                QPDF_LINEARIZE=1
            fi
            ;;

        encrypt)
            local user_pw="$OMC_ACTIONUI_VIEW_110_VALUE"
            local owner_pw="$OMC_ACTIONUI_VIEW_111_VALUE"
            local bits="$OMC_ACTIONUI_VIEW_112_VALUE"
            [ -z "$bits" ] && bits=256
            # Empty owner password would leave restrictions trivially removable;
            # default it to the user password.
            [ -z "$owner_pw" ] && owner_pw="$user_pw"

            # --allow-weak-crypto is a global flag: it must precede --encrypt
            if [ "$bits" != "256" ]; then
                QPDF_ARGS+=(--allow-weak-crypto)
            fi
            QPDF_ARGS+=(--encrypt "--user-password=$user_pw" "--owner-password=$owner_pw" "--bits=$bits")

            local allow_print="$OMC_ACTIONUI_VIEW_113_VALUE"
            local allow_modify="$OMC_ACTIONUI_VIEW_114_VALUE"
            local allow_extract="$OMC_ACTIONUI_VIEW_115_VALUE"
            local allow_annotate="$OMC_ACTIONUI_VIEW_116_VALUE"

            if [ "$bits" = "40" ]; then
                # 40-bit uses y/n permission flags
                [ "$allow_print" = "true" ]    && QPDF_ARGS+=(--print=y)    || QPDF_ARGS+=(--print=n)
                [ "$allow_modify" = "true" ]   && QPDF_ARGS+=(--modify=y)   || QPDF_ARGS+=(--modify=n)
                [ "$allow_extract" = "true" ]  && QPDF_ARGS+=(--extract=y)  || QPDF_ARGS+=(--extract=n)
                [ "$allow_annotate" = "true" ] && QPDF_ARGS+=(--annotate=y) || QPDF_ARGS+=(--annotate=n)
            else
                [ "$allow_print" = "true" ]    && QPDF_ARGS+=(--print=full) || QPDF_ARGS+=(--print=none)
                [ "$allow_modify" = "true" ]   && QPDF_ARGS+=(--modify=all) || QPDF_ARGS+=(--modify=none)
                [ "$allow_extract" = "true" ]  && QPDF_ARGS+=(--extract=y)  || QPDF_ARGS+=(--extract=n)
                [ "$allow_annotate" = "true" ] && QPDF_ARGS+=(--annotate=y) || QPDF_ARGS+=(--annotate=n)
                [ "$bits" = "128" ] && QPDF_ARGS+=(--use-aes=y)
            fi

            QPDF_ARGS+=(--)
            ;;

        decrypt)
            local password="$OMC_ACTIONUI_VIEW_120_VALUE"
            if [ -n "$password" ]; then
                QPDF_ARGS+=("--password=$password")
            fi
            if [ "$OMC_ACTIONUI_VIEW_121_VALUE" = "true" ]; then
                QPDF_ARGS+=(--remove-restrictions)
            else
                QPDF_ARGS+=(--decrypt)
            fi
            ;;
    esac
}
