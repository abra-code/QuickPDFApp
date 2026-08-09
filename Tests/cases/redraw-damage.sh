# redraw-damage.sh - what each engine destroys, measured rather than assumed.
#
# QuickPDF warns before Optimize runs its image stage, because that stage is
# `pdfutil reduce` and reduce reaches its result by REDRAWING the page content,
# which discards the outline and the annotations. The qpdf-only path does not.
#
# The warning itself, and the decision to show it, are tested in the applet's
# omctest suite. What is tested here is the claim underneath both: that the two
# engines really do differ this way. Without it the warning is unfalsifiable -
# it would keep passing if pdfutil were fixed tomorrow, and the suite would be
# endorsing a lie.
#
# Structure is read straight out of `pdfutil info` rather than through the app's
# pdf_structure_at_risk. Restating the two patterns is the price of a suite that
# never sources the applet, and the controls below are what keep the restatement
# honest: each pattern is proved to match a document that has the feature and
# not to match one that does not, so a pattern that silently matched nothing
# would fail here rather than turning every assertion green.

has_outline() {
    "$PDFUTIL" info "$1" 2>/dev/null \
        | /usr/bin/awk -F': ' '$1 == "outline items" && $2 != "0" { f = 1 } END { exit !f }'
}
# pdfutil always writes the plural, including "1 annotations". The page-line
# anchor matters: matching the bare word anywhere would fire on a document whose
# own path contains it, since info echoes the path back.
has_annotations() {
    "$PDFUTIL" info "$1" 2>/dev/null \
        | /usr/bin/awk '/^page [0-9]+: .* annotations/ { f = 1 } END { exit !f }'
}

# --- the detectors work, in both directions --------------------------------
if ! has_outline "$FIX/outlined.pdf"; then fail "has_outline cannot see the outlined fixture's outline"; fi
if has_outline "$FIX/text.pdf"; then fail "has_outline fires on a document with no outline"; fi
if ! has_annotations "$FIX/form-filled.pdf"; then fail "has_annotations cannot see the form fixture's field"; fi
if has_annotations "$FIX/text.pdf"; then fail "has_annotations fires on a plain document"; fi

D="$TMP/redraw"
require mkdir -p "$D" || return

# --- pdfutil reduce destroys both ------------------------------------------
#
# This is what the app warns about. The quality and dpi mirror what the Optimize
# panel sends, but nothing here depends on those exact numbers - redrawing is
# what discards the structure, not the compression settings.
# Both detectors answer "no" for a document they cannot read at all, so a reduce
# that produced garbage looks exactly like a reduce that discarded the
# structure. The output has to be shown READABLE before its emptiness means
# anything - without this, truncating the file to zero bytes leaves the whole
# case green while proving nothing.
expect_ok "$PDFUTIL" reduce -q 85 -r 150 --force -o "$D/reduced-form.pdf" "$FIX/form-filled.pdf"
expect_eq 0 "$(qpdf_check_code "$D/reduced-form.pdf")" "the reduced form document is still readable"
if has_annotations "$D/reduced-form.pdf"; then
    fail "pdfutil reduce KEPT the form field - the app's redraw warning is now wrong"
fi
expect_ok "$PDFUTIL" reduce -q 85 -r 150 --force -o "$D/reduced-outline.pdf" "$FIX/outlined.pdf"
expect_eq 0 "$(qpdf_check_code "$D/reduced-outline.pdf")" "the reduced outlined document is still readable"
if has_outline "$D/reduced-outline.pdf"; then
    fail "pdfutil reduce KEPT the outline - the app's redraw warning is now wrong"
fi

# --- the qpdf structural pass keeps both ------------------------------------
#
# Which is why the warning is scoped to the image toggle rather than to Optimize
# as a whole. These are the flags the app's structural pass sends; they are
# written out here rather than sourced, because the claim is about what a
# structural rewrite does in general, not about one exact command line.
qpdf_structural() { # <input> <output>
    "$QPDF" --compress-streams=y --recompress-flate --compression-level=9 \
        --object-streams=generate --remove-unreferenced-resources=yes "$1" "$2"
}

expect_ok qpdf_structural "$FIX/form-filled.pdf" "$D/qpdf-form.pdf"
if ! has_annotations "$D/qpdf-form.pdf"; then
    fail "the qpdf structural pass discarded the form field - the warning's scope is now wrong"
fi
expect_ok qpdf_structural "$FIX/outlined.pdf" "$D/qpdf-outline.pdf"
if ! has_outline "$D/qpdf-outline.pdf"; then
    fail "the qpdf structural pass discarded the outline - the warning's scope is now wrong"
fi

# The kept structure is not merely present in a broken file.
expect_eq 0 "$(qpdf_check_code "$D/qpdf-form.pdf")"    "qpdf --check on the structural pass output"
expect_eq 0 "$(qpdf_check_code "$D/qpdf-outline.pdf")" "qpdf --check on the structural pass output"
