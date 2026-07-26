# Bundled helper binaries - shape, self-containment, and crypto capability.
#
# These assert properties update_quickpdf.sh is supposed to guarantee about what
# ships in Contents/Helpers, checked against the bundle as it actually exists.

# Both helpers run and report a version.
expect_ok "$QPDF" --version
expect_ok "$PDFUTIL" --version

# Both are universal. A single-arch helper still works on the build machine and
# fails only for other users, so it has to be checked rather than assumed.
for tool in "$QPDF" "$PDFUTIL"; do
    expect_grep "arm64"  /usr/bin/lipo -archs "$tool"
    expect_grep "x86_64" /usr/bin/lipo -archs "$tool"
done

# Self-contained: no links against the libraries that are supposed to be static.
# A dylib reference here means the binary would break outside the build machine.
for tool in "$QPDF" "$PDFUTIL"; do
    expect_nogrep "libz\." /usr/bin/otool -L "$tool"
    expect_nogrep "libjpeg" /usr/bin/otool -L "$tool"
    expect_nogrep "libssl" /usr/bin/otool -L "$tool"
    expect_nogrep "libcrypto" /usr/bin/otool -L "$tool"
done

# Both are signed, so the bundle's signature can seal.
expect_ok /usr/bin/codesign -v "$QPDF"
expect_ok /usr/bin/codesign -v "$PDFUTIL"

# --- qpdf crypto capability -------------------------------------------------
#
# Regression guard for a real shipping bug: OpenSSL 3+ keeps RC4 in its "legacy"
# provider, and qpdf needs RC4 to derive the key for any /R 2-4 file (RC4-40,
# RC4-128, AES-128). When OpenSSL is configured with `no-shared` but not
# `no-module`, that provider is emitted as a separate legacy.dylib that a
# statically linked qpdf can never load, and qpdf then fails on those files with
# "unable to load openssl legacy provider" - which is most encrypted PDFs in the
# wild, including everything PDFKit writes. AES-256 (/R 6) keeps working
# throughout, because it only needs SHA-2 and AES from the default provider, so
# testing 256-bit alone does not catch this.
# qpdf's 128-bit is RC4-128 (/R 3) unless --use-aes=y is given, so this exercises
# the RC4 cipher itself, not merely RC4 key derivation - the most direct test of
# the capability that went missing.
expect_ok "$QPDF" --allow-weak-crypto --encrypt u o 128 -- "$FIX/text.pdf" "$TMP/h-rc4.pdf"
expect_grep "R = 3" "$QPDF" --show-encryption --password=u "$TMP/h-rc4.pdf"
# The diagnostic string itself, so a regression names its own cause in the output
# instead of only showing a missing "R = 3".
expect_nogrep "legacy provider" "$QPDF" --show-encryption --password=u "$TMP/h-rc4.pdf"
# A real operation on the RC4 file, since --show-encryption alone can print a
# dictionary without ever exercising the cipher.
expect_ok "$QPDF" --check --password=u "$TMP/h-rc4.pdf"
