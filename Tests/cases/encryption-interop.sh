# Encryption interop - each tool must read what the other writes.
#
# QuickPDF's Set Password and Decrypt operations run qpdf, while pdfutil handles
# other verbs on the same files, so a user can easily encrypt with one engine and
# process with the other. Neither project's own suite can test that boundary.

# --- qpdf encrypts, pdfutil reads ------------------------------------------
#
# All three bit depths, because they are three different security handlers with
# different key derivation: 40-bit is RC4 /R 2, 128-bit is AES /R 4 (RC4 key
# derivation), 256-bit is AES /R 6 (SHA-2, no RC4). The app offers all three.
#
# The revision each depth produces, asserted so the suite documents which security
# handler is actually being exercised: 40 -> /R 2 (RC4-40), 128 -> /R 3 (RC4-128,
# because qpdf only uses AES at 128 bits with --use-aes=y), 256 -> /R 6 (AESv3).
for bits in 40 128 256; do
    case "$bits" in
        40)  want_r="R = 2" ;;
        128) want_r="R = 3" ;;
        256) want_r="R = 6" ;;
    esac
    weak=""
    [ "$bits" = 256 ] || weak="--allow-weak-crypto"
    enc="$TMP/q$bits.pdf"
    expect_ok "$QPDF" $weak --encrypt secret owner "$bits" -- "$FIX/text.pdf" "$enc"
    expect_grep "$want_r" "$QPDF" --show-encryption --password=secret "$enc"

    # pdfutil opens it with the user password and sees the real text layer.
    expect_grep "PAGE-1-MARKER" "$PDFUTIL" text --password secret "$enc"
    expect_grep "encrypted: true" "$PDFUTIL" info --password secret "$enc"

    # ... and refuses it without a password (2 = processing error, not a crash).
    expect_code 2 "$PDFUTIL" text "$enc"

    # pdfutil can strip qpdf's encryption, and qpdf agrees the result is clear.
    dec="$TMP/q$bits-dec.pdf"
    expect_ok "$PDFUTIL" decrypt --password secret -o "$dec" "$enc"
    expect_grep "File is not encrypted" "$QPDF" --show-encryption "$dec"
    expect_grep "PAGE-1-MARKER" "$PDFUTIL" text "$dec"

    # The decrypted copy is still structurally sound to the other engine.
    expect_eq 0 "$(qpdf_check_code "$dec")" "qpdf --check on pdfutil-decrypted $bits-bit"
done

# --- pdfutil encrypts, qpdf reads ------------------------------------------
#
# pdfutil goes through PDFKit's writer, which emits /V 4 /R 4 with AESV2. Reading
# that requires RC4 for key derivation, so this direction is exactly what broke
# when qpdf shipped without OpenSSL's legacy provider.
enc="$TMP/p-enc.pdf"
expect_ok "$PDFUTIL" encrypt --user-password secret --owner-password owner -o "$enc" "$FIX/text.pdf"
expect_grep "R = 4" "$QPDF" --show-encryption --password=secret "$enc"
expect_grep "AESv2" "$QPDF" --show-encryption --password=secret "$enc"
expect_eq 0 "$(qpdf_check_code --password=secret "$enc")" "qpdf --check on pdfutil-encrypted"

# qpdf can strip pdfutil's encryption, and pdfutil agrees the result is clear.
expect_ok "$QPDF" --decrypt --password=secret "$enc" "$TMP/p-dec.pdf"
expect_grep "PAGE-1-MARKER" "$PDFUTIL" text "$TMP/p-dec.pdf"
expect_nogrep "encrypted: true" "$PDFUTIL" info "$TMP/p-dec.pdf"

# --- both tools agree on the wrong password --------------------------------
#
# Note qpdf's --show-encryption is deliberately lenient: it exits 0 on a bad
# password and prints "Incorrect password supplied" followed by the encryption
# dictionary, which it can read without the key. Any operation that needs to
# decrypt content exits 2. Both behaviours are asserted so neither is mistaken for
# the other.
expect_code 2 "$PDFUTIL" text --password wrong "$enc"
expect_grep "Incorrect password supplied" "$QPDF" --show-encryption --password=wrong "$enc"
expect_code 2 "$QPDF" --check --password=wrong "$enc"
expect_code 2 "$QPDF" --show-npages --password=wrong "$enc"

# --- permissions: where the two tools genuinely disagree -------------------
#
# Encrypt with only low-resolution printing allowed, then ask both tools what the
# file permits. They do not agree, and the divergence is asserted rather than
# avoided so that it stays documented and any change is noticed.
perm="$TMP/perm.pdf"
expect_ok "$QPDF" --encrypt --user-password=u --owner-password=o --bits=256 \
    --print=low --modify=none --extract=n --annotate=n -- "$FIX/text.pdf" "$perm"

# Ground truth is the /P value in the file: -3388 has bit 12 (2048, print
# high-resolution) clear, so high-quality printing is denied. qpdf reports that
# correctly.
expect_grep "/P -3388" /usr/bin/grep -ao "/P -[0-9]*" "$perm"
expect_grep "print low resolution: allowed"      "$QPDF" --show-encryption --password=u "$perm"
expect_grep "print high resolution: not allowed" "$QPDF" --show-encryption --password=u "$perm"
expect_grep "modify anything: not allowed"       "$QPDF" --show-encryption --password=u "$perm"

# pdfutil reports high-quality-printing as ALLOWED for the same file. This is not
# a mapping bug in pdfutil: it reports PDFKit's accessPermissions, and PDFKit
# returns raw=35 here, setting allowsHighQualityPrinting (2) even though /P bit 12
# is clear. PDFKit conflates the two print permissions, and pdfutil cannot see
# past it without parsing /P itself. Asserted as the known-wrong value: if a
# future macOS fixes PDFKit, this line fails and tells us to update it.
expect_grep "high-quality-printing" "$PDFUTIL" info --password u "$perm"

# The permissions both tools DO agree on, which is the useful part of the check.
expect_grep "printing" "$PDFUTIL" info --password u "$perm"
expect_nogrep "changes" "$PDFUTIL" info --password u "$perm"
expect_nogrep "copying" "$PDFUTIL" info --password u "$perm"
expect_nogrep "assembly" "$PDFUTIL" info --password u "$perm"
