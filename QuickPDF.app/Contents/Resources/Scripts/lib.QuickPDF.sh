#!/bin/bash
# lib.QuickPDF.sh - Shared functions and variables for QuickPDF

# Embedded qpdf binary
QPDF="$OMC_APP_BUNDLE_PATH/Contents/Helpers/qpdf"
# Embedded pdfutil binary; its `reduce` verb does Quartz image recompression /
# downsampling (formerly the standalone pdfreduce helper).
PDFUTIL="$OMC_APP_BUNDLE_PATH/Contents/Helpers/pdfutil"

# Control IDs
TABLE_ID=10
SUMMARY_VIEW_ID=12
REMOVE_BUTTON_ID=102
REVEAL_BUTTON_ID=104
PREVIEW_BUTTON_ID=105
INFO_BUTTON_ID=106

OPERATION_PICKER_ID=60

# Optimize controls
OPT_LINEARIZE_ID=70
OPT_COMPRESS_STREAMS_ID=71
OPT_RECOMPRESS_IMAGES_ID=72
OPT_JPEG_QUALITY_ID=73
OPT_OBJECT_STREAMS_ID=74
OPT_REMOVE_UNREF_ID=75
OPT_DOWNSAMPLE_ID=76
OPT_DPI_ID=77

# Encrypt controls
# Each password is typed twice: a mistyped user password is unrecoverable, since
# nothing in the tool can report what was actually typed and no one can open the
# result. The confirmation ids sit at 117/119 because the 110-119 encrypt band
# was already laid out when they were added.
ENC_USER_PW_ID=110
ENC_USER_PW_CONFIRM_ID=117
ENC_OWNER_PW_ID=111
ENC_OWNER_PW_CONFIRM_ID=119
ENC_BITS_ID=112
ENC_ALLOW_PRINT_ID=113
ENC_ALLOW_MODIFY_ID=114
ENC_ALLOW_EXTRACT_ID=115
ENC_ALLOW_ANNOTATE_ID=116
ENC_STRENGTH_NOTICE_ID=118

# Default key length. 128-bit AES is the compatibility floor that every reader
# still in service accepts; 256-bit is stronger but older readers refuse it.
ENC_DEFAULT_BITS=256

# Decrypt controls
DEC_PASSWORD_ID=120
DEC_RESTRICTIONS_ONLY_ID=121

# Rotate controls
ROTATE_ANGLE_PICKER_ID=130
ROTATE_RANGE_FIELD_ID=131

# Extract / Reorder controls
EXTRACT_RANGE_FIELD_ID=140

# Merge controls
MERGE_RANGE_FIELD_ID=141

# Split controls
SPLIT_CHUNK_FIELD_ID=150

# Repair controls
REPAIR_COALESCE_ID=180

# Remove-metadata controls
META_XMP_ID=190
META_INFO_ID=191
META_STRUCTURE_ID=192
META_PAGE_LABELS_ID=193

# Flatten controls
FLATTEN_MODE_PICKER_ID=195
FLATTEN_APPEARANCES_ID=196
FLATTEN_ROTATION_ID=197

# Operation GroupBox IDs (ZStack panel switcher)
GROUP_OPTIMIZE_ID=200
GROUP_ENCRYPT_ID=210
GROUP_DECRYPT_ID=220
GROUP_ROTATE_ID=240
GROUP_EXTRACT_ID=250
GROUP_SPLIT_ID=260
GROUP_MERGE_ID=270
GROUP_REPAIR_ID=280
GROUP_METADATA_ID=290
GROUP_FLATTEN_ID=300

RUN_BUTTON_ID=90

# Runtime tools
dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
next_cmd="$OMC_OMC_SUPPORT_PATH/omc_next_command"
alert_tool="$OMC_OMC_SUPPORT_PATH/alert"
pasteboard_tool="$OMC_OMC_SUPPORT_PATH/pasteboard"
window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

# Private pasteboard key: hands off the Open panel selection to the new
# window's init script
OPEN_PATHS_PB_KEY="QUICKPDF_OPEN_PATHS"

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

    # Outputs read by the caller via select_first_or_resync:
    #   LIST_WAS_EMPTY  1 if the table had no rows before this add
    #   FIRST_FILE_PATH full path of the first row after this add ("" if none)
    FIRST_FILE_PATH=""
    if [ -n "$OMC_ACTIONUI_TABLE_10_COLUMN_2_ALL_ROWS" ]; then
        LIST_WAS_EMPTY=0
    else
        LIST_WAS_EMPTY=1
    fi

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
        local sorted="$(printf "%s" "$buffer" | /usr/bin/sort -u)"
        printf "%s" "$sorted" | "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_set_rows_from_stdin
        # First row after sort = first table row; column 2 (tab field 2) is the path.
        FIRST_FILE_PATH="$(printf "%s" "$sorted" | /usr/bin/head -1 | /usr/bin/cut -f2)"
    else
        "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_remove_all_rows
    fi
}

# Update the detail pane (summary + per-file action buttons) for a selected
# file. Pass the file's full path, or "" when nothing is selected.
#
# Used two ways:
#   - the selection-changed handler passes the live table value (a real user
#     click);
#   - the add handlers pass the known first-row path after auto-selecting it.
# The add handlers call this directly rather than chaining
# QuickPDF.files.selection.changed, because omc_select_row fires no actionID
# AND a chained handler would race the (fire-and-forget) selection message on
# the host's main runloop — it could read the table value before the new
# selection is applied. Passing the path explicitly is race-free.
apply_file_selection() {
    local selected_path="$1"

    if [ -z "$selected_path" ]; then
        "$dialog_tool" "$window_uuid" ${REMOVE_BUTTON_ID} omc_disable
        "$dialog_tool" "$window_uuid" ${REVEAL_BUTTON_ID} omc_disable
        "$dialog_tool" "$window_uuid" ${PREVIEW_BUTTON_ID} omc_disable
        "$dialog_tool" "$window_uuid" ${INFO_BUTTON_ID} omc_disable
        return
    fi

    "$dialog_tool" "$window_uuid" ${REMOVE_BUTTON_ID} omc_enable
    "$dialog_tool" "$window_uuid" ${REVEAL_BUTTON_ID} omc_enable
    "$dialog_tool" "$window_uuid" ${PREVIEW_BUTTON_ID} omc_enable
    "$dialog_tool" "$window_uuid" ${INFO_BUTTON_ID} omc_enable

    if [ -e "$selected_path" ]; then
        local size="$(/usr/bin/stat -f %z "$selected_path" 2>/dev/null)"
        local pages="$("$QPDF" --show-npages "$selected_path" 2>/dev/null)"
        local encrypted="No"
        if "$QPDF" --is-encrypted "$selected_path" 2>/dev/null; then
            encrypted="Yes"
        fi
        set_summary "$(/usr/bin/basename "$selected_path")
Size: $(format_size "$size")
Pages: ${pages:-?}
Encrypted: $encrypted"
    fi
}

# Called by the add handlers right after add_files_to_table. If files were just
# added to a previously empty list, select and show the first row. Otherwise
# re-sync the detail pane to the live selection through the normal handler.
select_first_or_resync() {
    if [ "$LIST_WAS_EMPTY" = "1" ] && [ -n "$FIRST_FILE_PATH" ]; then
        # Visual selection only (fires no actionID); update the detail pane
        # directly from the known path to avoid the selection-vs-handler race.
        "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_select_row 0
        apply_file_selection "$FIRST_FILE_PATH"
    else
        "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "QuickPDF.files.selection.changed"
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

# Echo a path that does not exist yet. If the given path is taken, append
# " 2", " 3", … before the extension (or to the name for folders/extensionless).
# Arguments: desired path
unique_path() {
    local path="$1"
    if [ ! -e "$path" ]; then
        echo "$path"
        return
    fi
    local stem ext
    local dir="$(/usr/bin/dirname "$path")"
    local base="$(/usr/bin/basename "$path")"
    case "$base" in
        *.*)
            stem="${base%.*}"
            ext=".${base##*.}"
            ;;
        *)
            stem="$base"
            ext=""
            ;;
    esac
    local n=2
    local candidate="$dir/$stem $n$ext"
    while [ -e "$candidate" ]; do
        n=$((n + 1))
        candidate="$dir/$stem $n$ext"
    done
    echo "$candidate"
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

# Validate a positive integer DPI; echoes the clamped value (default on garbage)
# Arguments: value default
clamp_dpi() {
    local d="$1" def="$2"
    case "$d" in
        '' | *[!0-9]*) d="$def" ;;
        *)
            [ "$d" -lt 1 ] && d="$def"
            [ "$d" -gt 2400 ] && d=2400
            ;;
    esac
    echo "$d"
}

# Build the qpdf argument lists for the current operation into globals:
#   QPDF_ARGS      - flags placed before the input path
#   QPDF_POST_ARGS - flags placed between the input and output paths
#                    (e.g. --pages for extract)
#   QPDF_LINEARIZE - 1/0, optimize only: batch loop does the two-pass size check
# Arguments: operation tag (optimize|encrypt|decrypt|rotate|extract|split)
build_qpdf_args() {
    local op="$1"
    QPDF_ARGS=()
    QPDF_POST_ARGS=()
    QPDF_LINEARIZE=0
    # pdfutil reduce image stage (optimize only); consumed by optimize_file
    QPDF_RECOMPRESS_IMAGES=0
    QPDF_JPEG_QUALITY=85
    QPDF_DOWNSAMPLE_DPI=0

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
            # Image recompression is handled by pdfutil's reduce verb (Quartz
            # image filter) as a first stage, not qpdf: qpdf cannot downsample
            # and silently skips ICC/JPEG images. optimize_file runs it, then
            # the qpdf structural pass built above.
            if [ "$OMC_ACTIONUI_VIEW_72_VALUE" = "true" ]; then
                QPDF_RECOMPRESS_IMAGES=1
                QPDF_JPEG_QUALITY=$(clamp_quality "$OMC_ACTIONUI_VIEW_73_VALUE" 85)
                if [ "$OMC_ACTIONUI_VIEW_76_VALUE" = "true" ]; then
                    QPDF_DOWNSAMPLE_DPI=$(clamp_dpi "$OMC_ACTIONUI_VIEW_77_VALUE" 150)
                else
                    QPDF_DOWNSAMPLE_DPI=0
                fi
            fi
            if [ "$OMC_ACTIONUI_VIEW_70_VALUE" = "true" ]; then
                QPDF_LINEARIZE=1
            fi
            ;;

        encrypt)
            local user_pw="$OMC_ACTIONUI_VIEW_110_VALUE"
            local owner_pw="$OMC_ACTIONUI_VIEW_111_VALUE"
            local bits="$OMC_ACTIONUI_VIEW_112_VALUE"
            [ -z "$bits" ] && bits=$ENC_DEFAULT_BITS
            # Empty owner password would leave restrictions trivially removable;
            # default it to the user password.
            [ -z "$owner_pw" ] && owner_pw="$user_pw"

            # --allow-weak-crypto is a global flag: it must precede --encrypt.
            # qpdf refuses RC4 specifically, not "anything below 256" - 128-bit
            # AES needs no override. Scoping the flag to the only RC4 option we
            # offer keeps it off the default path, so it stays an accurate
            # signal that something genuinely weak is being written.
            #
            # This narrowing is only valid while --use-aes=y is emitted for
            # 128-bit further down: without it qpdf writes RC4-128 and refuses
            # the whole run with "refusing to write a file with RC4". The two
            # lines are 20 apart in different branches - change either and the
            # default path breaks. Tests/cases/encrypt-args.sh covers it.
            if [ "$bits" = "40" ]; then
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
                # Required, not cosmetic: 128-bit without this is RC4-128, which
                # qpdf refuses outright unless --allow-weak-crypto is also
                # passed - and that flag is now scoped to 40-bit only. See the
                # note beside that scoping above.
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

        rotate)
            local angle="$OMC_ACTIONUI_VIEW_130_VALUE"
            [ -z "$angle" ] && angle="+90"
            local range="$OMC_ACTIONUI_VIEW_131_VALUE"
            if [ -n "$range" ]; then
                QPDF_ARGS+=("--rotate=${angle}:${range}")
            else
                QPDF_ARGS+=("--rotate=${angle}")
            fi
            ;;

        extract)
            # range is validated as non-empty by QuickPDF.start.batch
            local range="$OMC_ACTIONUI_VIEW_140_VALUE"
            QPDF_POST_ARGS=(--pages . "$range" --)
            ;;

        split)
            local chunk="$OMC_ACTIONUI_VIEW_150_VALUE"
            case "$chunk" in
                '' | *[!0-9]* | 0) chunk=1 ;;
            esac
            QPDF_ARGS+=("--split-pages=$chunk")
            ;;

        repair)
            # A plain in -> out pass already rebuilds the file structure
            if [ "$OMC_ACTIONUI_VIEW_180_VALUE" = "true" ]; then
                QPDF_ARGS+=(--coalesce-contents)
            fi
            ;;

        metadata)
            [ "$OMC_ACTIONUI_VIEW_190_VALUE" = "true" ] && QPDF_ARGS+=(--remove-metadata)
            [ "$OMC_ACTIONUI_VIEW_191_VALUE" = "true" ] && QPDF_ARGS+=(--remove-info)
            [ "$OMC_ACTIONUI_VIEW_192_VALUE" = "true" ] && QPDF_ARGS+=(--remove-structure)
            [ "$OMC_ACTIONUI_VIEW_193_VALUE" = "true" ] && QPDF_ARGS+=(--remove-page-labels)
            ;;

        flatten)
            local fmode="$OMC_ACTIONUI_VIEW_195_VALUE"
            [ -z "$fmode" ] && fmode="all"
            # Appearance regeneration must happen before flattening
            if [ "$OMC_ACTIONUI_VIEW_196_VALUE" = "true" ]; then
                QPDF_ARGS+=(--generate-appearances)
            fi
            QPDF_ARGS+=("--flatten-annotations=$fmode")
            if [ "$OMC_ACTIONUI_VIEW_197_VALUE" = "true" ]; then
                QPDF_ARGS+=(--flatten-rotation)
            fi
            ;;
    esac
}

# Run one qpdf pass: run_qpdf input output
# Echoes qpdf's combined stderr/stdout; returns qpdf's exit code.
run_qpdf() {
    "$QPDF" "${QPDF_ARGS[@]}" "$1" "${QPDF_POST_ARGS[@]}" "$2" 2>&1
}

# Return 0 when the image stage actually produced a smaller file.
#
# pdfutil exiting 0 is not the same as pdfutil having helped. Its Quartz filter
# re-encodes only the images it RESCALES, so on a document whose images are
# already small enough to leave alone it can hand back something no better than
# the input - and older builds returned something several times LARGER, having
# decoded the JPEGs and stored them losslessly. Newer builds notice that and
# return the original bytes instead, which lands here as "not smaller" too.
#
# Comparing sizes covers both behaviors, so this works whichever pdfutil is
# embedded rather than depending on the newer one being deployed first.
#
# Arguments: original path, reduced path
image_stage_helped() {
    local before after
    before="$(/usr/bin/stat -f %z "$1" 2>/dev/null)"
    after="$(/usr/bin/stat -f %z "$2" 2>/dev/null)"
    [ -n "$before" ] && [ -n "$after" ] || return 1
    # A 0-byte result means the run produced nothing usable, not a perfect
    # compression; mktemp pre-creates the file, so this is reachable.
    [ "$after" -gt 0 ] || return 1
    [ "$after" -lt "$before" ]
}

# Full optimize pipeline for one file: an optional pdfutil reduce image stage
# followed by the qpdf structural pass, including the linearize keep-if-smaller
# two-pass. Writes the result to $2 (a caller-provided temp path). Echoes the
# tool output for the caller's summary; returns an exit code compatible with the
# run scripts (0 ok, 3 qpdf warnings, 2 fatal, other = error).
#
# Called inside a command substitution, so QPDF_ARGS mutations here stay local
# to the subshell; file writes/moves still take effect.
optimize_file() {
    local input="$1" final_out="$2"
    local work_dir; work_dir="$(/usr/bin/dirname "$final_out")"
    local src="$input" reduced=""

    if [ "$QPDF_RECOMPRESS_IMAGES" = "1" ]; then
        reduced="$(/usr/bin/mktemp "$work_dir/.quickpdf.XXXXXX")"
        local pr_out
        # pdfutil reduce edits in place by default and takes the output via -o;
        # mktemp pre-created $reduced (0 bytes) so --force is needed to overwrite it.
        pr_out="$("$PDFUTIL" reduce -q "$QPDF_JPEG_QUALITY" -r "$QPDF_DOWNSAMPLE_DPI" \
                  --force -o "$reduced" "$input" 2>&1)"
        if [ $? -ne 0 ]; then
            /bin/rm -f "$reduced"
            printf 'pdfutil reduce: %s\n' "$(printf '%s' "$pr_out" | /usr/bin/head -1)"
            return 2
        fi
        if image_stage_helped "$input" "$reduced"; then
            src="$reduced"
        else
            # pdfutil could not improve on these images, so fall back to qpdf's
            # own image optimizer for this file. It is the weaker tool - it skips
            # ICC/JPEG scans and never downsamples, which is exactly why the
            # image stage moved to pdfutil in the first place - but on the
            # documents pdfutil declines it is the one that still has something
            # to offer, and the alternative is shipping the images untouched.
            #
            # Added to the structural pass that is about to run rather than
            # spawned as a third invocation: qpdf is going to open and rewrite
            # this file either way. QPDF_ARGS is safe to mutate here because
            # optimize_file runs inside a command substitution (see above), the
            # same reason --linearize can be appended below.
            /bin/rm -f "$reduced"
            reduced=""
            QPDF_ARGS+=(--optimize-images "--jpeg-quality=$QPDF_JPEG_QUALITY" \
                        --oi-min-width=64 --oi-min-height=64)
        fi
    fi

    local out; out="$(run_qpdf "$src" "$final_out")"
    local code=$?

    if [ "$QPDF_LINEARIZE" = "1" ] && [ $code -ne 2 ]; then
        local tmp_linear; tmp_linear="$(/usr/bin/mktemp "$work_dir/.quickpdf.XXXXXX")"
        QPDF_ARGS+=(--linearize)
        local lin_out; lin_out="$(run_qpdf "$src" "$tmp_linear")"
        local lin_code=$?
        if [ $lin_code -ne 2 ]; then
            local plain_size linear_size
            plain_size="$(/usr/bin/stat -f %z "$final_out")"
            linear_size="$(/usr/bin/stat -f %z "$tmp_linear")"
            if [ "$linear_size" -le "$plain_size" ]; then
                /bin/mv -f "$tmp_linear" "$final_out"
                # The delivered file now comes from the linearized pass, so
                # report its status/warnings rather than the first pass's.
                out="$lin_out"
                code=$lin_code
            else
                /bin/rm -f "$tmp_linear"
            fi
        else
            /bin/rm -f "$tmp_linear"
        fi
    fi

    [ -n "$reduced" ] && /bin/rm -f "$reduced"
    printf '%s' "$out"
    return $code
}

