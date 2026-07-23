#!/bin/bash
# update_quickpdf.sh
# Build QuickPDF's embedded command-line helpers and re-sign the applet.
#
# Two helpers live in QuickPDF.app/Contents/Helpers:
#   * qpdf    - built statically (no dylib deps) from source by the vendored
#               qpdf/build-qpdf-static.sh wrapper, which downloads and compiles
#               zlib, libjpeg-turbo, OpenSSL, and qpdf itself. Heavy (several
#               minutes), so it is OPT-IN: pass --with-qpdf (or it auto-builds when
#               no qpdf is embedded yet). Otherwise the existing qpdf is reused.
#   * pdfutil - built by its sibling repo's build.sh (plain swiftc, system
#               frameworks only). Its `reduce` verb provides the Quartz image
#               recompression / downsampling that the retired pdfreduce did, which
#               QuickPDF's Optimize pipeline (optimize_file in lib.QuickPDF.sh)
#               now calls. Fast, so it is rebuilt every run unless --skip-build.
#
# Both are built UNIVERSAL (arm64 + x86_64) to match QuickPDF.app, so nothing is
# thinned. Codesigning is delegated to codesign_applet.sh.
#
# The .app bundle is auto-detected from this script's directory.

set -uo pipefail

GREEN=$(printf '\033[92m'); RED=$(printf '\033[91m'); YELLOW=$(printf '\033[93m'); RESET=$(printf '\033[0m')

SIGNING_IDENTITY="-"
DO_BUILD="yes"
DO_CODESIGN="yes"
DO_QPDF="no"          # opt-in; also auto-enabled below when no qpdf is embedded yet
QPDF_VERSION=""       # empty = let the wrapper auto-detect the latest stable qpdf

SCRIPT_DIR="$(cd "$(/usr/bin/dirname "$0")" >/dev/null 2>&1 && pwd)"
PDFUTIL_REPO="${PDFUTIL_REPO:-}"
QPDF_WRAPPER_DIR="$SCRIPT_DIR/qpdf"

while [ $# -gt 0 ]; do
    case "$1" in
        --pdfutil-repo=*) PDFUTIL_REPO="${1#*=}" ;;
        --skip-build) DO_BUILD="no" ;;
        --with-qpdf) DO_QPDF="yes" ;;
        --qpdf-version=*) DO_QPDF="yes"; QPDF_VERSION="${1#*=}" ;;
        --identity=*) SIGNING_IDENTITY="${1#*=}" ;;
        --no-codesign) DO_CODESIGN="no" ;;
        --help)
            echo "Usage: $0 [--with-qpdf] [--qpdf-version=VER] [--pdfutil-repo=PATH] [--skip-build] [--identity=CERT] [--no-codesign]"
            echo
            echo "  --with-qpdf          rebuild the static qpdf via qpdf/build-qpdf-static.sh and embed it"
            echo "                       (slow; auto-enabled when no qpdf is embedded yet)"
            echo "  --qpdf-version=VER   build a specific qpdf version (implies --with-qpdf; default: latest stable)"
            echo "  --pdfutil-repo=PATH  pdfutil source repo (default: sibling ../pdfutil, or \$PDFUTIL_REPO)"
            echo "  --skip-build         reuse the already-deployed pdfutil binary (does not affect qpdf)"
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
# Both the helper tools and their third-party license texts live in Contents/Helpers.
# Helpers is a nested-code location, so codesign requires each loose file there to be
# individually signed before the bundle can seal - which the vendored codesign_applet.sh
# now handles (it signs loose non-Mach-O files in nested locations, then the Mach-O, the
# nested bundles, and finally the app). So no per-file signing is needed in this script.
RES_DIR="$APP_BUNDLE/Contents/Resources"

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

# Auto-enable the qpdf build when the bundle has no qpdf to reuse (fresh checkout:
# Helpers/ is gitignored). An explicit --skip-build does not suppress this - without
# a qpdf there is nothing to sign or ship.
if [ "$DO_QPDF" != "yes" ] && [ ! -x "$HELPERS_DIR/qpdf" ]; then
    echo "  (no embedded qpdf found - enabling the qpdf build)"
    DO_QPDF="yes"
fi

echo
echo "==== Updating $(basename "$APP_BUNDLE") (universal) ===="
echo "  qpdf     : $([ "$DO_QPDF" = "yes" ] && echo "build via $QPDF_WRAPPER_DIR/build-qpdf-static.sh" || echo "reuse embedded")"
echo "  pdfutil  : ${PDFUTIL_REPO:-<not located>}"
echo "  deploy to: $HELPERS_DIR"
echo

# --- 1. Build + embed the static qpdf helper ------------------------------
# The vendored wrapper downloads + statically compiles zlib, libjpeg-turbo, OpenSSL
# and qpdf, emitting a self-contained universal binary at
# qpdf/qpdf-static-universal/bin/qpdf (no dylib refs into the build tree). We embed
# just qpdf (QuickPDF does not use the fix-qdf / zlib-flate side tools).
if [ "$DO_QPDF" = "yes" ]; then
    [ -x "$QPDF_WRAPPER_DIR/build-qpdf-static.sh" ] || fail "qpdf build wrapper not found at $QPDF_WRAPPER_DIR/build-qpdf-static.sh"
    _qpdf_args=(--arch=universal)
    [ -n "$QPDF_VERSION" ] && _qpdf_args+=("--qpdf-version=$QPDF_VERSION")
    # Force a pristine build. The wrapper reconfigures each dependency in place and
    # is not re-run-safe: a second build over a prior run's tree fails to link
    # OpenSSL (stale per-arch objects -> "_FMT_istext" undefined). Remove the
    # extracted source dirs so every build starts clean, matching the known-good
    # first-run path; the downloaded *.tar.gz are kept and simply re-extracted, so
    # this costs a recompile but no re-download.
    if [ -d "$QPDF_WRAPPER_DIR/sources" ]; then
        /usr/bin/find "$QPDF_WRAPPER_DIR/sources" -mindepth 1 -maxdepth 1 -type d -exec /bin/rm -rf {} +
    fi
    echo "  Building static qpdf (downloads + compiles OpenSSL etc; this takes several minutes)..."
    ( cd "$QPDF_WRAPPER_DIR" && ./build-qpdf-static.sh "${_qpdf_args[@]}" ) || fail "qpdf build failed"
    _qpdf_built="$QPDF_WRAPPER_DIR/qpdf-static-universal/bin/qpdf"
    [ -x "$_qpdf_built" ] || fail "qpdf build produced no binary at $_qpdf_built"
    # Confirm the fresh build is universal and self-contained before shipping it.
    _qarchs="$(/usr/bin/lipo -archs "$_qpdf_built" 2>/dev/null)"
    case " $_qarchs " in
        *" arm64 "*) case " $_qarchs " in *" x86_64 "*) ;; *) fail "qpdf is not universal (archs: $_qarchs)" ;; esac ;;
        *) fail "qpdf is not universal (archs: $_qarchs)" ;;
    esac
    if /usr/bin/otool -L "$_qpdf_built" | /usr/bin/grep -v "^$_qpdf_built" | /usr/bin/grep -qE '(libz|libjpeg|libssl|libcrypto)\.dylib'; then
        fail "qpdf links dependency dylibs - static build is not self-contained."
    fi
    /bin/mkdir -p "$HELPERS_DIR" || fail "Could not create $HELPERS_DIR"
    /bin/cp -f "$_qpdf_built" "$HELPERS_DIR/qpdf" || fail "Could not copy qpdf"
    /bin/chmod +x "$HELPERS_DIR/qpdf"
    echo "  ${GREEN}Built${RESET} qpdf (universal: $_qarchs; $("$HELPERS_DIR/qpdf" --version 2>/dev/null | /usr/bin/head -1))"

    # Attribution for the libraries statically linked into qpdf. Their license texts
    # come from the wrapper's extracted sources (present after a build); copy them
    # beside qpdf in Contents/Helpers so the credit in Credits.rtf points at real
    # files. Pick the newest matching tree in case sources/ holds more than one version.
    _srcdir="$QPDF_WRAPPER_DIR/sources"
    _embed_dep_license() {   # $1 = license glob, $2 = destination basename
        local _m; _m="$(/bin/ls -t $1 2>/dev/null | /usr/bin/head -1)"
        if [ -n "$_m" ] && [ -f "$_m" ]; then
            /bin/cp -f "$_m" "$HELPERS_DIR/$2" && echo "  embedded $2"
            /bin/rm -f "$RES_DIR/$2"   # retire any copy left in Resources by older builds
        else
            echo "${YELLOW}  WARNING: no license file for $2 (looked for $1)${RESET}"
        fi
    }
    _embed_dep_license "$_srcdir/zlib-*/LICENSE"           "zlib.LICENSE"
    _embed_dep_license "$_srcdir/libjpeg-turbo-*/LICENSE.md" "libjpeg-turbo.LICENSE"
    _embed_dep_license "$_srcdir/openssl-*/LICENSE.txt"    "openssl.LICENSE"
fi
[ -x "$HELPERS_DIR/qpdf" ] || fail "No qpdf at $HELPERS_DIR/qpdf (pass --with-qpdf to build it)."

# --- 2. Build + embed the pdfutil helper ----------------------------------
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
    if [ -f "$PDFUTIL_REPO/LICENSE" ]; then
        /bin/cp -f "$PDFUTIL_REPO/LICENSE" "$HELPERS_DIR/pdfutil.LICENSE"
        /bin/rm -f "$RES_DIR/pdfutil.LICENSE"   # retire any copy left in Resources by older builds
    fi
    /bin/rm -f "$HELPERS_DIR/pdfreduce"   # retire the old helper on upgrade
    echo "  ${GREEN}Built${RESET} pdfutil (universal: $_archs)"
fi
[ -x "$HELPERS_DIR/pdfutil" ] || fail "No pdfutil at $HELPERS_DIR/pdfutil (build first, or drop --skip-build)."

# Sweep Finder droppings out of Helpers before signing.
/usr/bin/find "$HELPERS_DIR" -name ".DS_Store" -delete 2>/dev/null

# --- 3. Codesign ----------------------------------------------------------
# codesign_applet.sh is the sole signer. It deep-signs the bundle and, as of the
# vendored version here, also signs loose non-Mach-O files in nested-code locations
# (the qpdf/pdfutil license texts sitting beside the tools in Contents/Helpers), so
# no per-file pre-signing is needed in this script. It also auto-discovers
# OMCApplet.entitlements beside the bundle.
if [ "$DO_CODESIGN" = "yes" ]; then
    [ -x "$SCRIPT_DIR/codesign_applet.sh" ] || fail "codesign_applet.sh not found beside this script"
    "$SCRIPT_DIR/codesign_applet.sh" "$APP_BUNDLE" "$SIGNING_IDENTITY" \
        || fail "codesign_applet.sh failed"
fi

# --- 4. Verify ------------------------------------------------------------
# qpdf --version proves the embedded binary launches after signing.
if "$HELPERS_DIR/qpdf" --version 2>/dev/null | /usr/bin/grep -q "^qpdf version "; then
    echo "  ${GREEN}Verify OK${RESET}: qpdf launches ($("$HELPERS_DIR/qpdf" --version 2>/dev/null | /usr/bin/head -1))"
else
    fail "qpdf did not report its version - build/link/sign failure."
fi
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
