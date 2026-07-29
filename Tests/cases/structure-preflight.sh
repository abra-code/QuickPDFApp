# The Optimize structure pre-flight.
#
# Two separate claims are tested here, and the second is the one that matters:
#
#   1. pdf_structure_at_risk reports what a document has to lose.
#   2. Optimize's image stage really does destroy it, and the qpdf-only path
#      really does not.
#
# Without (2) the guard is unfalsifiable - it would keep passing if pdfutil were
# fixed tomorrow, and the warning would then be a lie the suite endorses.

(
    # Subshell: sourcing the lib defines control-ID constants and helper
    # functions the other case files have no reason to inherit.
    OMC_APP_BUNDLE_PATH="$APP"
    OMC_OMC_SUPPORT_PATH="/nonexistent"
    export OMC_APP_BUNDLE_PATH OMC_OMC_SUPPORT_PATH
    . "$LIB"

    P="$TMP/preflight"
    require mkdir -p "$P" || return

    # --- what the fixtures actually carry ------------------------------------
    #
    # form-filled.pdf has one form field, which `info` counts as an annotation.
    # text.pdf and scan.pdf are plain. No fixture here has an outline, so that
    # arm is exercised against one built below.
    expect_eq "annotations" "$(pdf_structure_at_risk "$FIX/form-filled.pdf")" \
        "form-filled.pdf is at risk"
    expect_eq "" "$(pdf_structure_at_risk "$FIX/text.pdf")" \
        "text.pdf has nothing to lose"
    expect_eq "" "$(pdf_structure_at_risk "$FIX/scan.pdf")" \
        "scan.pdf has nothing to lose"

    # An unreadable file must read as "nothing at risk" rather than blocking the
    # run over a question the guard could not answer.
    expect_eq "" "$(pdf_structure_at_risk "$P/does-not-exist.pdf")" \
        "a missing file is not reported as at risk"
    printf 'not a pdf at all\n' > "$P/notes.txt"
    expect_eq "" "$(pdf_structure_at_risk "$P/notes.txt")" \
        "a non-PDF is not reported as at risk"

    # --- the outline arm -----------------------------------------------------
    expect_eq "outline" "$(pdf_structure_at_risk "$FIX/outlined.pdf")" \
        "outlined.pdf is at risk for its outline"

    # Both at once. Adding a form field to the outlined fixture is the only way
    # to reach the combined string through the real parser rather than by
    # calling structure_risk_phrase with a hand-written argument.
    require cp "$FIX/outlined.pdf" "$P/both.pdf" || return
    expect_ok "$PDFUTIL" watermark --text "draft" --annotation --force \
        -o "$P/both.pdf" "$FIX/outlined.pdf"
    expect_eq "outline annotations" "$(pdf_structure_at_risk "$P/both.pdf")" \
        "a document with both is reported as both"

    # --- the phrases ---------------------------------------------------------
    expect_eq "an outline" "$(structure_risk_phrase "outline")" "phrase: outline"
    expect_eq "annotations or form fields" "$(structure_risk_phrase "annotations")" \
        "phrase: annotations"
    expect_eq "an outline and annotations or form fields" \
        "$(structure_risk_phrase "outline annotations")" "phrase: both"
    # Anything unmapped still completes the sentence "<FILE> has ...".
    expect_eq "structure that will not survive" \
        "$(structure_risk_phrase "something new")" "phrase: fallback"

    # --- optimize_redraws keys on the image toggle, not the operation --------
    OMC_ACTIONUI_VIEW_60_VALUE="optimize"; OMC_ACTIONUI_VIEW_72_VALUE="true"
    export OMC_ACTIONUI_VIEW_60_VALUE OMC_ACTIONUI_VIEW_72_VALUE
    expect_ok optimize_redraws

    OMC_ACTIONUI_VIEW_72_VALUE="false"
    expect_fail optimize_redraws

    # No other operation REDRAWS, so none of them warns even with the Optimize
    # toggle left on. Some of them still remove things - Flatten takes out form
    # fields, Remove metadata can take out the structure tree - but that is the
    # operation doing what the user selected, which is not what this guard is
    # about.
    OMC_ACTIONUI_VIEW_72_VALUE="true"
    for op in encrypt decrypt rotate extract split merge repair metadata flatten; do
        OMC_ACTIONUI_VIEW_60_VALUE="$op"
        expect_fail optimize_redraws
    done

    # An untouched operation picker reports "" and means optimize.
    OMC_ACTIONUI_VIEW_60_VALUE=""
    expect_ok optimize_redraws

    # --- the claim the warning rests on --------------------------------------
    #
    # pdfutil reduce is what QuickPDF's image stage runs. If this ever stops
    # destroying structure, the warning above becomes wrong and this fails.
    expect_ok "$PDFUTIL" reduce -q 85 -r 150 --force \
        -o "$P/reduced.pdf" "$FIX/form-filled.pdf"
    expect_eq "" "$(pdf_structure_at_risk "$P/reduced.pdf")" \
        "pdfutil reduce discards the form field (this is what the warning is for)"

    # ...and the qpdf-only path does NOT, which is why the guard is scoped to
    # the image toggle rather than to Optimize as a whole.
    expect_ok "$QPDF" --compress-streams=y --object-streams=generate \
        --optimize-images "$FIX/form-filled.pdf" "$P/qpdf-only.pdf"
    expect_eq "annotations" "$(pdf_structure_at_risk "$P/qpdf-only.pdf")" \
        "the qpdf structural pass keeps the form field"

    # The outline too, which is the example the alert text leads with.
    expect_ok "$QPDF" --compress-streams=y --object-streams=generate \
        --optimize-images "$FIX/outlined.pdf" "$P/qpdf-only-outline.pdf"
    expect_eq "outline" "$(pdf_structure_at_risk "$P/qpdf-only-outline.pdf")" \
        "the qpdf structural pass keeps the outline"
    expect_eq "" "$(pdf_structure_at_risk "$P/reduced-outline.pdf" 2>/dev/null)" \
        "sanity: an unbuilt path reads as nothing at risk"
    expect_ok "$PDFUTIL" reduce -q 85 -r 150 --force \
        -o "$P/reduced-outline.pdf" "$FIX/outlined.pdf"
    expect_eq "" "$(pdf_structure_at_risk "$P/reduced-outline.pdf")" \
        "pdfutil reduce discards the outline as well as the form field"
)
