#!/bin/sh
# Build pdfreduce as a universal (x86_64 + arm64) binary and, if a destination
# app is given, copy it into that app's Contents/Helpers.
#
# Usage:
#   ./build.sh                       # build ./pdfreduce (universal)
#   ./build.sh ../../QuickPDF.app    # build and install into the app's Helpers

set -e

self_dir=$(cd "$(dirname "$0")" && pwd)
src="$self_dir/pdfreduce.swift"
out="$self_dir/pdfreduce"
min_macos="12.0"

build_slice() {
    arch="$1"
    echo "Building $arch slice..."
    xcrun -sdk macosx swiftc -O \
        -target "${arch}-apple-macos${min_macos}" \
        -framework Foundation -framework CoreGraphics -framework Quartz \
        "$src" -o "$out-$arch"
}

build_slice x86_64
build_slice arm64

echo "Creating universal binary..."
lipo -create -output "$out" "$out-x86_64" "$out-arm64"
rm -f "$out-x86_64" "$out-arm64"
lipo -info "$out"

app="$1"
if [ -n "$app" ]; then
    helpers="$app/Contents/Helpers"
    if [ ! -d "$helpers" ]; then
        echo "error: $helpers does not exist" >&2
        exit 1
    fi
    echo "Installing to $helpers/pdfreduce"
    cp "$out" "$helpers/pdfreduce"
fi

echo "Done."
