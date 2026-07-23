#!/bin/bash
# update_quickpdf.sh
# Build the pdfutil helper (github.com/abra-code/pdfutil, Apache 2.0) and embed it
# into QuickPDF.app/Contents/Helpers, replacing the retired standalone pdfreduce.
#
# pdfutil's `reduce` verb now provides the Quartz-based image recompression /
# downsampling that pdfreduce was written for, so QuickPDF's Optimize pipeline
# (optimize_file in lib.QuickPDF.sh) calls `pdfutil reduce` instead. This script
# builds that one binary universal, drops it beside the embedded qpdf, retires the
# old pdfreduce binary, then hands the whole bundle to codesign_applet.sh.
#
# QuickPDF.app ships UNIVERSAL (arm64 + x86_64), so nothing is thinned: pdfutil is
# built universal too and the app is signed as-is.
#
# The .app bundle is auto-detected from this script's directory.

set -uo pipefail

GREEN=$(printf '\033[92m'); RED=$(printf '\033[91m'); YELLOW=$(printf '\033[93m'); RESET=$(printf '\033[0m')

SIGNING_IDENTITY="-"
DO_BUILD="yes"
DO_CODESIGN="yes"

SCRIPT_DIR="$(cd "$(/usr/bin/dirname "$0")" >/dev/null 2>&1 && pwd)"
PDFUTIL_REPO="${PDFUTIL_REPO:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        --pdfutil-repo=*) PDFUTIL_REPO="${1#*=}" ;;
        --skip-build) DO_BUILD="no" ;;
        --identity=*) SIGNING_IDENTITY="${1#*=}" ;;
        --no-codesign) DO_CODESIGN="no" ;;
        --help)
            echo "Usage: $0 [--pdfutil-repo=PATH] [--skip-build] [--identity=CERT] [--no-codesign]"
            echo
            echo "  --pdfutil-repo=PATH  pdfutil source repo (default: sibling ../pdfutil, or \$PDFUTIL_REPO)"
            echo "  --skip-build         reuse the already-deployed pdfutil binary"
            echo "  --identity=CERT      codesign identity passed to codesign_applet.sh ('-' = ad-hoc, default)"
            echo "  --no-codesign        skip the codesign_applet.sh step"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

fail() { echo "${RED}$*${RESET}" >&2; exit 1; }

# A dependency repo is missing: offer to git-clone it into the sibling location and
# continue. Interactive runs only - without a TTY (CI, piped stdin) this declines
# silently and the caller's fail() fires with the manual instructions.
# $1 = repo URL, $2 = destination dir.
offer_clone() {
    [ -t 0 ] || return 1
    printf "%s  %s not found. Clone %s\n  into %s now? [y/N] %s" \
        "$YELLOW" "$(/usr/bin/basename "$2")" "$1" "$2" "$RESET"
    IFS= read -r _ans
    case "$_ans" in [yY]|[yY][eE][sS]) ;; *) return 1 ;; esac
    /usr/bin/git clone "$1" "$2"
}

# Auto-detect the single .app bundle beside this script.
APP_BUNDLE=""
for _c in "$SCRIPT_DIR"/*.app; do [ -d "$_c" ] && { APP_BUNDLE="$_c"; break; }; done
[ -n "$APP_BUNDLE" ] || fail "No .app bundle found in $SCRIPT_DIR"
HELPERS_DIR="$APP_BUNDLE/Contents/Helpers"

# Locate the pdfutil repo: env/flag override, then sibling dir, offering to clone
# it there when missing (only when a build is requested - --skip-build reuses the
# already-deployed binary). Built by the repo's own build.sh (plain swiftc, system
# frameworks only, universal by default).
if [ -z "$PDFUTIL_REPO" ]; then
    for _cand in "$SCRIPT_DIR/../pdfutil"; do
        [ -f "$_cand/build.sh" ] && [ -d "$_cand/Sources" ] && { PDFUTIL_REPO="$(cd "$_cand" && pwd)"; break; }
    done
fi
if [ -z "$PDFUTIL_REPO" ] && [ "$DO_BUILD" = "yes" ]; then
    offer_clone "https://github.com/abra-code/pdfutil" "$(cd "$SCRIPT_DIR/.." && pwd)/pdfutil" \
        && [ -f "$SCRIPT_DIR/../pdfutil/build.sh" ] \
        && PDFUTIL_REPO="$(cd "$SCRIPT_DIR/../pdfutil" && pwd)"
fi

echo
echo "==== Updating $(basename "$APP_BUNDLE") (universal) ===="
echo "  pdfutil  : ${PDFUTIL_REPO:-<not located>}"
echo "  deploy to: $HELPERS_DIR"
echo

# --- 1. Build + embed the pdfutil helper ----------------------------------
# pdfutil's build.sh with no arg produces a universal (arm64 + x86_64) binary at
# build/pdfutil, ad-hoc signed. Copy it beside qpdf with its LICENSE, and retire
# the old standalone pdfreduce binary on upgrade.
if [ "$DO_BUILD" = "yes" ]; then
    [ -n "$PDFUTIL_REPO" ] || fail "pdfutil repo not found (looked for build.sh + Sources); clone github.com/abra-code/pdfutil beside this repo or pass --pdfutil-repo=PATH"
    ( cd "$PDFUTIL_REPO" && ./build.sh ) || fail "pdfutil build.sh failed"
    _built="$PDFUTIL_REPO/build/pdfutil"
    [ -x "$_built" ] || fail "pdfutil build produced no binary at $_built"
    # Confirm the fresh build really is universal before shipping it.
    _archs="$(/usr/bin/lipo -archs "$_built" 2>/dev/null)"
    case " $_archs " in
        *" arm64 "*) case " $_archs " in *" x86_64 "*) ;; *) fail "pdfutil is not universal (archs: $_archs)" ;; esac ;;
        *) fail "pdfutil is not universal (archs: $_archs)" ;;
    esac
    /bin/mkdir -p "$HELPERS_DIR" || fail "Could not create $HELPERS_DIR"
    /bin/cp -f "$_built" "$HELPERS_DIR/pdfutil" || fail "Could not copy pdfutil"
    /bin/chmod +x "$HELPERS_DIR/pdfutil"
    [ -f "$PDFUTIL_REPO/LICENSE" ] && /bin/cp -f "$PDFUTIL_REPO/LICENSE" "$HELPERS_DIR/pdfutil.LICENSE"
    /bin/rm -f "$HELPERS_DIR/pdfreduce"   # retire the old helper on upgrade
    echo "  ${GREEN}Built${RESET} pdfutil (universal: $_archs)"
fi
[ -x "$HELPERS_DIR/pdfutil" ] || fail "No pdfutil at $HELPERS_DIR/pdfutil (build first, or drop --skip-build)."

# Sweep Finder droppings out of Helpers before signing.
/usr/bin/find "$HELPERS_DIR" -name ".DS_Store" -delete 2>/dev/null

# --- 2. Codesign ----------------------------------------------------------
# codesign_applet.sh deep-signs every nested Mach-O and the app itself, and
# auto-discovers OMCApplet.entitlements beside the bundle - so the freshly copied
# pdfutil binary is covered without any per-binary handling here.
#
# But Contents/Helpers is a NON-STANDARD bundle location, so codesign treats each
# loose file there as a nested subcomponent that must carry its own signature
# before the app bundle can be sealed (the qpdf LICENSE.txt/NOTICE.md already do).
# codesign_applet.sh's Mach-O pass does not sign plain text files, so pre-sign the
# license we just added; otherwise sealing the bundle fails on the unsigned file.
if [ "$DO_CODESIGN" = "yes" ]; then
    [ -x "$SCRIPT_DIR/codesign_applet.sh" ] || fail "codesign_applet.sh not found beside this script"
    if [ -f "$HELPERS_DIR/pdfutil.LICENSE" ]; then
        /usr/bin/codesign --force --timestamp=none --sign "$SIGNING_IDENTITY" "$HELPERS_DIR/pdfutil.LICENSE" \
            || fail "Could not pre-sign pdfutil.LICENSE"
    fi
    "$SCRIPT_DIR/codesign_applet.sh" "$APP_BUNDLE" "$SIGNING_IDENTITY" \
        || fail "codesign_applet.sh failed"
fi

# --- 3. Verify ------------------------------------------------------------
# pdfutil --version prints "pdfutil <ver>" and exits 0; that proves the binary
# loads (system frameworks linked). Match the output, not just the exit code.
if "$HELPERS_DIR/pdfutil" --version 2>/dev/null | /usr/bin/grep -q "^pdfutil "; then
    echo "  ${GREEN}Verify OK${RESET}: pdfutil launches ($("$HELPERS_DIR/pdfutil" --version 2>/dev/null))"
else
    fail "pdfutil did not report its version - build/link failure."
fi
# The reduce verb is what QuickPDF's Optimize pipeline depends on; confirm it exists.
if "$HELPERS_DIR/pdfutil" reduce --help 2>&1 | /usr/bin/grep -q -- "--quality"; then
    echo "  ${GREEN}Verify OK${RESET}: pdfutil reduce verb present"
else
    fail "pdfutil has no working 'reduce' verb - wrong/old build?"
fi

echo
echo "  ${GREEN}Done.${RESET} $(basename "$APP_BUNDLE") is ready."
echo
