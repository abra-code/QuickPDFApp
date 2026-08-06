#!/bin/bash
# ================================================
# Build qpdf + dependencies statically for macOS
# Supports: arm64, x86_64, universal
# Versions default to "auto" (latest stable via GitHub API).
# ================================================

ZLIB_VERSION="auto"
JPEG_VERSION="auto"
OPENSSL_VERSION="auto"
QPDF_VERSION="auto"
NASM_VERSION="auto"
ARCH="universal"

show_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --arch=ARCH                  Architecture: universal, arm64, or x86_64 (default: universal)
  --zlib-version=VERSION       zlib version (default: auto-detect latest stable)
  --jpeg-version=VERSION       libjpeg-turbo version (default: auto-detect latest stable)
  --openssl-version=VERSION    OpenSSL version (default: auto-detect latest stable)
  --qpdf-version=VERSION       qpdf version (default: auto-detect latest stable)
  --nasm-version=VERSION       NASM version for x86_64 SIMD (default: auto-detect latest stable)
  --help                       Show this help message

Examples:
  $0
  $0 --arch=arm64
  $0 --qpdf-version=12.3.2 --arch=universal
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --help)             show_help ;;
    --arch=*)           ARCH="${1#*=}" ;;
    --zlib-version=*)   ZLIB_VERSION="${1#*=}" ;;
    --jpeg-version=*)   JPEG_VERSION="${1#*=}" ;;
    --openssl-version=*) OPENSSL_VERSION="${1#*=}" ;;
    --qpdf-version=*)   QPDF_VERSION="${1#*=}" ;;
    --nasm-version=*)   NASM_VERSION="${1#*=}" ;;
    *)
      echo "Unknown option: $1"
      show_help
      ;;
  esac
  shift
done

if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" && "$ARCH" != "universal" ]]; then
  echo "❌ Error: --arch must be arm64, x86_64 or universal"
  exit 1
fi

# Set architectures for CMake
if [[ "$ARCH" == "universal" ]]; then
  CMAKE_ARCHS="arm64;x86_64"
elif [[ "$ARCH" == "arm64" ]]; then
  CMAKE_ARCHS="arm64"
else
  CMAKE_ARCHS="x86_64"
fi

PREFIX="$(pwd)/qpdf-static-$ARCH"
BUILD_JOBS=$(/usr/sbin/sysctl -n hw.logicalcpu)

mkdir -p sources "$PREFIX"
cd sources

# CMake detection
if [[ -x "/Applications/CMake.app/Contents/bin/cmake" ]]; then
  CMAKE="/Applications/CMake.app/Contents/bin/cmake"
elif [[ -x "/usr/local/bin/cmake" ]]; then
  CMAKE="/usr/local/bin/cmake"
elif [[ -x "/opt/homebrew/bin/cmake" ]]; then
  CMAKE="/opt/homebrew/bin/cmake"
else
  echo "❌ CMake not found. Please install CMake first."
  exit 1
fi

echo "Using CMake: $CMAKE"

# ===================== DOWNLOAD FUNCTION =====================
download() {
    local url=$1
    local output=$2
    echo "⬇️  Downloading: $output"

    local i
    for i in {1..3}; do
        /usr/bin/curl -L --fail --silent --show-error -o "$output" "$url"
        if [[ $? -eq 0 ]]; then
            local size=$(/usr/bin/stat -f %z "$output" 2>/dev/null || /usr/bin/stat -c %s "$output" 2>/dev/null)
            echo "   ✓ Downloaded ($((size/1024)) KB)"
            return 0
        else
            echo "   ⚠️  Attempt $i failed. Retrying..."
            sleep 2
        fi
    done
    echo "❌ Failed to download $url"
    return 1
}

# ===================== VERSION DETECTION =====================
# Two-strategy approach (same pattern as Python-Embedding):
#   1. Follow the /releases/latest redirect and parse the tag from the URL.
#   2. Fall back to the GitHub releases/tags JSON API.

_releases_latest_redirect() {
    # Returns the redirect URL from /releases/latest (empty on failure).
    /usr/bin/curl -s --head -w '%{redirect_url}' \
        "https://github.com/$1/releases/latest" 2>/dev/null || echo ""
}

_releases_latest_api_tag() {
    # Returns raw tag_name from the GitHub releases/latest JSON API (empty on failure).
    local json
    json=$(/usr/bin/curl -s --fail --max-time 10 \
        "https://api.github.com/repos/$1/releases/latest" 2>/dev/null || echo "")
    if [[ "$json" =~ \"tag_name\":\ *\"([^\"]+)\" ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

_tags_api_latest() {
    # Returns the first tag_name matching <pattern> from /tags API (for repos without Releases).
    local repo="$1" pattern="$2"
    local json
    json=$(/usr/bin/curl -s --fail --max-time 10 \
        "https://api.github.com/repos/$repo/tags?per_page=20" 2>/dev/null || echo "")
    local tag
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ \"name\":\ *\"($pattern)\" ]]; then
            echo "${BASH_REMATCH[1]}"
            return
        fi
    done <<< "$json"
}

detect_latest_zlib() {
    echo "Detecting latest zlib version..."
    local url; url=$(_releases_latest_redirect "madler/zlib")
    if [[ "$url" =~ /tag/v([0-9]+\.[0-9]+(\.[0-9]+)?)$ ]]; then
        ZLIB_VERSION="${BASH_REMATCH[1]}"; echo "  Detected: $ZLIB_VERSION"; return
    fi
    local tag; tag=$(_releases_latest_api_tag "madler/zlib")
    if [[ "$tag" =~ ^v([0-9]+\.[0-9]+(\.[0-9]+)?)$ ]]; then
        ZLIB_VERSION="${BASH_REMATCH[1]}"; echo "  Detected via API: $ZLIB_VERSION"; return
    fi
    ZLIB_VERSION="1.3.2"
    echo "  Detection failed — falling back to $ZLIB_VERSION"
}

detect_latest_jpeg() {
    echo "Detecting latest libjpeg-turbo version..."
    # libjpeg-turbo uses four-part versions (e.g. 3.1.4.1) — match X.Y.Z or X.Y.Z.W.
    local url; url=$(_releases_latest_redirect "libjpeg-turbo/libjpeg-turbo")
    if [[ "$url" =~ /tag/([0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?)$ ]]; then
        JPEG_VERSION="${BASH_REMATCH[1]}"; echo "  Detected: $JPEG_VERSION"; return
    fi
    local tag; tag=$(_releases_latest_api_tag "libjpeg-turbo/libjpeg-turbo")
    if [[ "$tag" =~ ^([0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?)$ ]]; then
        JPEG_VERSION="${BASH_REMATCH[1]}"; echo "  Detected via API: $JPEG_VERSION"; return
    fi
    JPEG_VERSION="3.1.4.1"
    echo "  Detection failed — falling back to $JPEG_VERSION"
}

detect_latest_openssl() {
    echo "Detecting latest OpenSSL version..."
    local url; url=$(_releases_latest_redirect "openssl/openssl")
    if [[ "$url" =~ /tag/openssl-([^/]+)$ ]]; then
        OPENSSL_VERSION="${BASH_REMATCH[1]}"; echo "  Detected: $OPENSSL_VERSION"; return
    fi
    local tag; tag=$(_releases_latest_api_tag "openssl/openssl")
    if [[ "$tag" =~ ^openssl-([^/]+)$ ]]; then
        OPENSSL_VERSION="${BASH_REMATCH[1]}"; echo "  Detected via API: $OPENSSL_VERSION"; return
    fi
    OPENSSL_VERSION="3.4.5"
    echo "  Detection failed — falling back to $OPENSSL_VERSION"
}

detect_latest_qpdf() {
    echo "Detecting latest qpdf version..."
    local url; url=$(_releases_latest_redirect "qpdf/qpdf")
    if [[ "$url" =~ /tag/v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        QPDF_VERSION="${BASH_REMATCH[1]}"; echo "  Detected: $QPDF_VERSION"; return
    fi
    local tag; tag=$(_releases_latest_api_tag "qpdf/qpdf")
    if [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        QPDF_VERSION="${BASH_REMATCH[1]}"; echo "  Detected via API: $QPDF_VERSION"; return
    fi
    QPDF_VERSION="12.3.2"
    echo "  Detection failed — falling back to $QPDF_VERSION"
}

detect_latest_nasm() {
    echo "Detecting latest NASM version..."
    # NASM may not publish GitHub Releases, only tags — try redirect, then API, then tags.
    local url; url=$(_releases_latest_redirect "netwide-assembler/nasm")
    if [[ "$url" =~ /tag/nasm-([0-9]+\.[0-9]+(\.[0-9]+)?)$ ]]; then
        NASM_VERSION="${BASH_REMATCH[1]}"; echo "  Detected: $NASM_VERSION"; return
    fi
    local tag; tag=$(_releases_latest_api_tag "netwide-assembler/nasm")
    if [[ "$tag" =~ ^nasm-([0-9]+\.[0-9]+(\.[0-9]+)?)$ ]]; then
        NASM_VERSION="${BASH_REMATCH[1]}"; echo "  Detected via API: $NASM_VERSION"; return
    fi
    # Last resort: tags list. The numeric-only pattern already rejects rc/pre/alpha/beta tags.
    tag=$(_tags_api_latest "netwide-assembler/nasm" "nasm-[0-9]+[.][0-9]+([.][0-9]+)?")
    if [[ "$tag" =~ ^nasm-([0-9]+\.[0-9]+([.][0-9]+)?)$ ]]; then
        NASM_VERSION="${BASH_REMATCH[1]}"; echo "  Detected via tags: $NASM_VERSION"; return
    fi
    NASM_VERSION="3.01"
    echo "  Detection failed — falling back to $NASM_VERSION"
}

# ===================== RESOLVE VERSIONS =====================
echo "=== Resolving component versions ==="
[[ "$ZLIB_VERSION"    == "auto" ]] && detect_latest_zlib
[[ "$JPEG_VERSION"    == "auto" ]] && detect_latest_jpeg
[[ "$OPENSSL_VERSION" == "auto" ]] && detect_latest_openssl
[[ "$QPDF_VERSION"    == "auto" ]] && detect_latest_qpdf
if [[ "$NASM_VERSION" == "auto" ]]; then
  if [[ "$ARCH" == "universal" || "$ARCH" == "x86_64" ]]; then
    detect_latest_nasm
  else
    NASM_VERSION="3.01"
  fi
fi
echo ""

echo "=== Building qpdf $QPDF_VERSION ($ARCH) statically ==="
echo "Using versions:"
echo "   zlib             : $ZLIB_VERSION"
echo "   libjpeg-turbo    : $JPEG_VERSION"
echo "   OpenSSL          : $OPENSSL_VERSION"
echo "   qpdf             : $QPDF_VERSION"
echo ""

# ===================== DOWNLOAD SOURCES =====================
echo "=== Downloading sources ==="

[[ ! -f "zlib-${ZLIB_VERSION}.tar.gz" ]] && \
  { download "https://zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz" "zlib-${ZLIB_VERSION}.tar.gz" || exit 1; }
[[ ! -f "libjpeg-turbo-${JPEG_VERSION}.tar.gz" ]] && \
  { download "https://github.com/libjpeg-turbo/libjpeg-turbo/archive/refs/tags/${JPEG_VERSION}.tar.gz" \
             "libjpeg-turbo-${JPEG_VERSION}.tar.gz" || exit 1; }
[[ ! -f "openssl-${OPENSSL_VERSION}.tar.gz" ]] && \
  { download "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" \
             "openssl-${OPENSSL_VERSION}.tar.gz" || exit 1; }
[[ ! -f "qpdf-${QPDF_VERSION}.tar.gz" ]] && \
  { download "https://github.com/qpdf/qpdf/releases/download/v${QPDF_VERSION}/qpdf-${QPDF_VERSION}.tar.gz" \
             "qpdf-${QPDF_VERSION}.tar.gz" || exit 1; }

# ===================== NASM (for x86_64 libjpeg-turbo SIMD) =====================
# Downloaded locally; not installed system-wide since x86 SIMD is legacy on modern macOS.
NASM_BIN=""
if [[ "$ARCH" == "universal" || "$ARCH" == "x86_64" ]]; then
  NASM_ZIP="nasm-${NASM_VERSION}-macosx.zip"
  if [[ ! -f "$NASM_ZIP" ]]; then
    download "https://www.nasm.us/pub/nasm/releasebuilds/${NASM_VERSION}/macosx/${NASM_ZIP}" "$NASM_ZIP" || true
  fi
  if [[ -f "$NASM_ZIP" ]] && [[ ! -f "nasm-${NASM_VERSION}/nasm" ]]; then
    /usr/bin/unzip -q -o "$NASM_ZIP" "nasm-${NASM_VERSION}/nasm" 2>/dev/null || \
      /usr/bin/unzip -q -o "$NASM_ZIP" 2>/dev/null || true
  fi
  if [[ -f "nasm-${NASM_VERSION}/nasm" ]]; then
    chmod +x "nasm-${NASM_VERSION}/nasm"
    NASM_BIN="$(pwd)/nasm-${NASM_VERSION}/nasm"
    echo "   Using NASM: $NASM_BIN"
  else
    echo "⚠️  NASM not available — x86_64 libjpeg-turbo will build without SIMD"
  fi
fi

# ===================== EXTRACT =====================
echo "=== Extracting archives ==="

[[ ! -d "zlib-${ZLIB_VERSION}" ]] && \
  { /usr/bin/tar -xzf "zlib-${ZLIB_VERSION}.tar.gz" || { echo "❌ Failed to extract zlib"; exit 1; }; }
[[ ! -d "libjpeg-turbo-${JPEG_VERSION}" ]] && \
  { /usr/bin/tar -xzf "libjpeg-turbo-${JPEG_VERSION}.tar.gz" || { echo "❌ Failed to extract libjpeg-turbo"; exit 1; }; }
[[ ! -d "openssl-${OPENSSL_VERSION}" ]] && \
  { /usr/bin/tar -xzf "openssl-${OPENSSL_VERSION}.tar.gz" || { echo "❌ Failed to extract OpenSSL"; exit 1; }; }
[[ ! -d "qpdf-${QPDF_VERSION}" ]] && \
  { /usr/bin/tar -xzf "qpdf-${QPDF_VERSION}.tar.gz" || { echo "❌ Failed to extract qpdf"; exit 1; }; }

echo "=== Building dependencies ==="

DEPS_PREFIX="$PREFIX/deps"
DEPLOYMENT_TARGET="11.0"
export MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"

# ===================== ZLIB =====================
echo "🔨 Building zlib ${ZLIB_VERSION}..."
cd "zlib-${ZLIB_VERSION}"

if [[ "$ARCH" == "universal" ]]; then
  CFLAGS="-fPIC -arch arm64 -mmacosx-version-min=$DEPLOYMENT_TARGET" \
    ./configure --static --prefix="$DEPS_PREFIX/zlib-arm64" || { echo "❌ zlib arm64 configure failed"; exit 1; }
  /usr/bin/make -j$BUILD_JOBS && /usr/bin/make install || { echo "❌ zlib arm64 build failed"; exit 1; }
  /usr/bin/make distclean

  CFLAGS="-fPIC -arch x86_64 -mmacosx-version-min=$DEPLOYMENT_TARGET" \
    ./configure --static --prefix="$DEPS_PREFIX/zlib-x86" || { echo "❌ zlib x86_64 configure failed"; exit 1; }
  /usr/bin/make -j$BUILD_JOBS && /usr/bin/make install || { echo "❌ zlib x86_64 build failed"; exit 1; }

  mkdir -p "$DEPS_PREFIX/zlib/lib"
  /usr/bin/lipo -create "$DEPS_PREFIX/zlib-arm64/lib/libz.a" "$DEPS_PREFIX/zlib-x86/lib/libz.a" \
    -output "$DEPS_PREFIX/zlib/lib/libz.a"
  cp -R "$DEPS_PREFIX/zlib-arm64/include" "$DEPS_PREFIX/zlib/"
else
  CFLAGS="-fPIC -mmacosx-version-min=$DEPLOYMENT_TARGET" \
    ./configure --static --prefix="$DEPS_PREFIX/zlib" || { echo "❌ zlib configure failed"; exit 1; }
  /usr/bin/make -j$BUILD_JOBS && /usr/bin/make install || { echo "❌ zlib build failed"; exit 1; }
fi

cd ..

# ===================== LIBJPEG-TURBO =====================
# libjpeg-turbo (special handling for universal)
echo "🔨 Building libjpeg-turbo ${JPEG_VERSION}..."
cd "libjpeg-turbo-${JPEG_VERSION}"

if [[ "$ARCH" == "universal" ]]; then
    echo "   Building libjpeg-turbo for arm64 and x86_64 separately..."
    
    # Build arm64
    "$CMAKE" -B build-arm64 -G "Unix Makefiles" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX/jpeg-arm64" \
      -DCMAKE_OSX_ARCHITECTURES="arm64" \
      -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
      -DENABLE_SHARED=OFF -DENABLE_STATIC=ON
    "$CMAKE" --build build-arm64 -j$BUILD_JOBS
    "$CMAKE" --install build-arm64

    # Build x86_64 (NASM needed for SIMD; fall back to no-SIMD if unavailable)
    X86_NASM_FLAG=""
    if [[ -n "$NASM_BIN" ]]; then
      X86_NASM_FLAG="-DCMAKE_ASM_NASM_COMPILER=$NASM_BIN"
    else
      X86_NASM_FLAG="-DWITH_SIMD=0"
    fi
    "$CMAKE" -B build-x86 -G "Unix Makefiles" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX/jpeg-x86" \
      -DCMAKE_OSX_ARCHITECTURES="x86_64" \
      -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
      -DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
      $X86_NASM_FLAG
    "$CMAKE" --build build-x86 -j$BUILD_JOBS
    "$CMAKE" --install build-x86

    # Combine with lipo
    mkdir -p "$DEPS_PREFIX/jpeg/lib"
    /usr/bin/lipo -create "$DEPS_PREFIX/jpeg-arm64/lib/libjpeg.a" "$DEPS_PREFIX/jpeg-x86/lib/libjpeg.a" \
            -output "$DEPS_PREFIX/jpeg/lib/libjpeg.a"
    cp -R "$DEPS_PREFIX/jpeg-arm64/include" "$DEPS_PREFIX/jpeg/"
    
else
    # Single architecture build
    "$CMAKE" -B build -G "Unix Makefiles" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX/jpeg" \
      -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
      -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
      -DENABLE_SHARED=OFF -DENABLE_STATIC=ON
    "$CMAKE" --build build -j$BUILD_JOBS
    "$CMAKE" --install build
fi

cd ..

# ===================== OPENSSL =====================
echo "🔨 Building OpenSSL ${OPENSSL_VERSION}..."
cd "openssl-${OPENSSL_VERSION}"

# no-module is required, not cosmetic. OpenSSL 3+ keeps RC4 (and the other
# deprecated algorithms) in the "legacy" provider, and qpdf needs RC4 to derive
# the key for /R 2-4 encrypted files - i.e. every PDF written with RC4-40/128 or
# AES-128, which is what most producers (including macOS PDFKit) still emit.
# providers/build.info only compiles the legacy provider *into* libcrypto when
# the `module` option is disabled; `no-shared` alone does not do that, so the
# provider is emitted as lib/ossl-modules/legacy.dylib instead. A statically
# linked qpdf then has no way to load it and dies with "unable to load openssl
# legacy provider" on any such file. no-module makes legacy built-in, which also
# registers it in ossl_predefined_providers so OSSL_PROVIDER_load(ctx,"legacy")
# resolves without a module file on disk.
_openssl_build() {
  local target="$1" prefix="$2"
  ./Configure "$target" no-shared no-module no-tests \
    -mmacosx-version-min="$DEPLOYMENT_TARGET" \
    --prefix="$prefix" --openssldir="$prefix" || { echo "❌ OpenSSL Configure failed ($target)"; exit 1; }
  /usr/bin/make -j$BUILD_JOBS || { echo "❌ OpenSSL make failed ($target)"; exit 1; }
  /usr/bin/make install_sw || { echo "❌ OpenSSL install failed ($target)"; exit 1; }

  # Fail loudly if the legacy provider did not get linked in - otherwise the
  # breakage only surfaces much later, as a runtime error on RC4 files.
  if ! /usr/bin/nm "$prefix/lib/libcrypto.a" 2>/dev/null | grep -q "ossl_legacy_provider_init"; then
    echo "❌ OpenSSL built without a built-in legacy provider ($target) - qpdf could not read RC4/AES-128 PDFs"
    exit 1
  fi
}

if [[ "$ARCH" == "universal" ]]; then
  _openssl_build darwin64-arm64-cc "$DEPS_PREFIX/openssl-arm64"
  /usr/bin/make clean
  _openssl_build darwin64-x86_64-cc "$DEPS_PREFIX/openssl-x86"

  mkdir -p "$DEPS_PREFIX/openssl/lib"
  /usr/bin/lipo -create "$DEPS_PREFIX/openssl-arm64/lib/libssl.a"   "$DEPS_PREFIX/openssl-x86/lib/libssl.a"   -output "$DEPS_PREFIX/openssl/lib/libssl.a"
  /usr/bin/lipo -create "$DEPS_PREFIX/openssl-arm64/lib/libcrypto.a" "$DEPS_PREFIX/openssl-x86/lib/libcrypto.a" -output "$DEPS_PREFIX/openssl/lib/libcrypto.a"
  cp -R "$DEPS_PREFIX/openssl-arm64/include" "$DEPS_PREFIX/openssl/"
elif [[ "$ARCH" == "arm64" ]]; then
  _openssl_build darwin64-arm64-cc "$DEPS_PREFIX/openssl"
else
  _openssl_build darwin64-x86_64-cc "$DEPS_PREFIX/openssl"
fi

cd ..

# ===================== QPDF =====================
echo "🔨 Building qpdf ${QPDF_VERSION}..."
cd "qpdf-${QPDF_VERSION}"

mkdir -p build && cd build

echo "   Running CMake configuration..."
"$CMAKE" -S .. -B . \
  -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  -DCMAKE_OSX_ARCHITECTURES="$CMAKE_ARCHS" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_PREFIX_PATH="$DEPS_PREFIX/zlib;$DEPS_PREFIX/jpeg;$DEPS_PREFIX/openssl" \
  -DZLIB_H_PATH="$DEPS_PREFIX/zlib/include" \
  -DZLIB_LIB_PATH="$DEPS_PREFIX/zlib/lib/libz.a" \
  -DLIBJPEG_H_PATH="$DEPS_PREFIX/jpeg/include" \
  -DLIBJPEG_LIB_PATH="$DEPS_PREFIX/jpeg/lib/libjpeg.a" \
  -DOPENSSL_ROOT_DIR="$DEPS_PREFIX/openssl" \
  -DOPENSSL_USE_STATIC_LIBS=ON \
  -DCMAKE_FIND_LIBRARY_SUFFIXES=".a" \
  ..

if [[ $? -ne 0 ]]; then echo "❌ qpdf CMake failed"; exit 1; fi

echo "   Building qpdf (this may take several minutes)..."
/usr/bin/make -j$BUILD_JOBS
if [[ $? -ne 0 ]]; then echo "❌ qpdf make failed"; exit 1; fi

/usr/bin/make install
if [[ $? -ne 0 ]]; then echo "❌ qpdf install failed"; exit 1; fi

# ===================== SMOKE TESTS =====================
echo ""
echo "=== Running smoke tests ==="

QPDF_BIN="$PREFIX/bin/qpdf"
SMOKE_TMP=$(mktemp -d)
trap 'rm -rf "$SMOKE_TMP"' EXIT

_pass=0; _fail=0

_check() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "  ✅ $desc"
        ((_pass++))
    else
        echo "  ❌ $desc"
        ((_fail++))
    fi
}

# --- Binary basics ---
_check "qpdf --version runs" "$QPDF_BIN" --version

detected_ver=$("$QPDF_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [[ "$detected_ver" == "$QPDF_VERSION" ]]; then
    echo "  ✅ Version matches build ($detected_ver)"
    ((_pass++))
else
    echo "  ❌ Version mismatch: binary reports $detected_ver, expected $QPDF_VERSION"
    ((_fail++))
fi

# --- Architecture ---
if [[ "$ARCH" == "universal" ]]; then
    _check "Fat binary contains arm64"  bash -c "/usr/bin/lipo -archs '$QPDF_BIN' | grep -qw arm64"
    _check "Fat binary contains x86_64" bash -c "/usr/bin/lipo -archs '$QPDF_BIN' | grep -qw x86_64"
else
    _check "Architecture is $ARCH" bash -c "/usr/bin/lipo -archs '$QPDF_BIN' 2>/dev/null | grep -qw '$ARCH'"
fi

# --- Static linking: no references to our build tree ---
_check "No dynamic refs into build tree" bash -c \
    "! /usr/bin/otool -L '$QPDF_BIN' | grep -v '^$QPDF_BIN' | grep -qE '(libz|libjpeg|libssl|libcrypto)\\.dylib'"

# --- Core PDF operations ---
# qpdf --check / --linearize need a real page tree: a 0-page `--empty` document
# fails --check with "ERROR: vector", so exercise those verbs against an embedded
# minimal 1-page PDF (decoded below) rather than the empty document.
SAMPLE="$SMOKE_TMP/sample.pdf"
/usr/bin/base64 -d > "$SAMPLE" <<'SAMPLE_PDF_B64'
JVBERi0xLjQKJb/3ov4KMSAwIG9iago8PCAvUGFnZXMgMiAwIFIgL1R5cGUgL0NhdGFsb2cgPj4K
ZW5kb2JqCjIgMCBvYmoKPDwgL0NvdW50IDEgL0tpZHMgWyAzIDAgUiBdIC9UeXBlIC9QYWdlcyA+
PgplbmRvYmoKMyAwIG9iago8PCAvTWVkaWFCb3ggWyAwIDAgNjEyIDc5MiBdIC9QYXJlbnQgMiAw
IFIgL1Jlc291cmNlcyA8PCA+PiAvVHlwZSAvUGFnZSA+PgplbmRvYmoKeHJlZgowIDQKMDAwMDAw
MDAwMCA2NTUzNSBmIAowMDAwMDAwMDE1IDAwMDAwIG4gCjAwMDAwMDAwNjQgMDAwMDAgbiAKMDAw
MDAwMDEyMyAwMDAwMCBuIAp0cmFpbGVyIDw8IC9Sb290IDEgMCBSIC9TaXplIDQgL0lEIFs8ZjMx
YjhlOGFmMWNkN2I3Y2NhOGZiNzYxNzdkOTlmYjA+PGYzMWI4ZThhZjFjZDdiN2NjYThmYjc2MTc3
ZDk5ZmIwPl0gPj4Kc3RhcnR4cmVmCjIxMwolJUVPRgo=
SAMPLE_PDF_B64

_check "Create empty PDF"    "$QPDF_BIN" --empty "$SMOKE_TMP/empty.pdf"
_check "Check sample PDF"    "$QPDF_BIN" --check "$SAMPLE"
_check "Linearize PDF"       "$QPDF_BIN" --linearize "$SAMPLE" "$SMOKE_TMP/linearized.pdf"
_check "Check linearized"    "$QPDF_BIN" --check "$SMOKE_TMP/linearized.pdf"

# --- Encryption / decryption ---
_check "Encrypt AES-256"     "$QPDF_BIN" --encrypt userpass ownerpass 256 -- \
                             "$SAMPLE" "$SMOKE_TMP/encrypted.pdf"
_check "Decrypt with password" "$QPDF_BIN" --decrypt --password=userpass \
                             "$SMOKE_TMP/encrypted.pdf" "$SMOKE_TMP/decrypted.pdf"
_check "Check decrypted PDF" "$QPDF_BIN" --check "$SMOKE_TMP/decrypted.pdf"

# AES-256 (/R 6) only exercises SHA-2 and AES, both in the default provider, so
# it passes even when the legacy provider is missing. /R 4 is the case that needs
# RC4 for key derivation, so these two are the real regression test for it.
# --allow-weak-crypto is needed because qpdf refuses to *write* RC4 by default.
_check "Encrypt AES-128 (/R 4, needs legacy provider)" \
                             "$QPDF_BIN" --allow-weak-crypto \
                             --encrypt userpass ownerpass 128 -- \
                             "$SAMPLE" "$SMOKE_TMP/enc128.pdf"
_check "Read back /R 4 file (RC4 key derivation)" \
                             "$QPDF_BIN" --show-encryption --password=userpass \
                             "$SMOKE_TMP/enc128.pdf"

# Verify that decrypted output is functionally equivalent (same page count)
orig_pages=$("$QPDF_BIN" --show-npages "$SAMPLE" 2>/dev/null)
dec_pages=$("$QPDF_BIN" --show-npages "$SMOKE_TMP/decrypted.pdf" 2>/dev/null)
if [[ "$orig_pages" == "$dec_pages" ]]; then
    echo "  ✅ Page count preserved after encrypt/decrypt ($orig_pages page(s))"
    ((_pass++))
else
    echo "  ❌ Page count mismatch: original=$orig_pages decrypted=$dec_pages"
    ((_fail++))
fi

# --- Rosetta check for universal builds (verifies x86_64 slice actually runs) ---
if [[ "$ARCH" == "universal" ]] && [[ "$(/usr/bin/uname -m)" == "arm64" ]]; then
    if /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
        _check "Runs under Rosetta (x86_64 slice)" \
            /usr/bin/arch -x86_64 "$QPDF_BIN" --version
    else
        echo "  ⚠️  Rosetta not available — skipping x86_64 slice test"
    fi
fi

# --- Summary ---
echo ""
if [[ $_fail -eq 0 ]]; then
    echo "✅ All $_pass smoke tests passed"
else
    echo "❌ $_fail of $((_pass + _fail)) smoke tests FAILED — see above"
    exit 1
fi

# ===================== FINAL REPORT =====================
echo ""
echo "========================================"
echo "✅ Build completed successfully!"
echo "Binary location : $PREFIX/bin/qpdf"
echo "Architecture    : $ARCH"
echo "Size            : $(/usr/bin/stat -f %z "$PREFIX/bin/qpdf" 2>/dev/null || echo "unknown") bytes"
echo ""
echo "Linked libraries:"
/usr/bin/otool -L "$PREFIX/bin/qpdf" 2>/dev/null || echo "otool not available"
echo "========================================"
