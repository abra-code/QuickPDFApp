# encryption-limits.sh - the qpdf encryption behavior the app's guards exist for.
#
# Three properties of qpdf's own encryption, each of which QuickPDF works around
# in code. The workarounds are tested in the applet's omctest suite; what is
# tested HERE is that they are still necessary, because a guard against behavior
# that no longer exists is a guard nobody can justify keeping.
#
# Nothing in this file sources the app's libraries or builds an argument list
# with them. Every call goes straight to the embedded binary.

# --- 32 characters is where 40-bit and 128-bit stop looking ----------------
#
# /R 2-4 derive the key from at most the first 32 bytes of the password, so a
# different long password sharing that prefix opens the file. /R 6 (AES-256)
# does not. This is why 256-bit is the default rather than merely the strongest
# option on offer.
#
# The two truncating writes are asserted SILENT as well as successful, because
# silence is what forces the app to explain the rule in its own alert text. If a
# future qpdf starts saying "password truncated" itself, those lines fail and
# the notice can defer to qpdf instead of restating it.
long_pw="abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGH"   # 44 characters
other_pw="abcdefghijklmnopqrstuvwxyz012345ZZZZZZZZZZZZ"   # same first 32
near_pw="abcdefghijklmnopqrstuvwxyz01234YYYYYYYYYYYYY"    # same first 31 only

expect_ok "$QPDF" --encrypt --user-password="$long_pw" \
    --owner-password="$long_pw" --bits=256 -- "$FIX/text.pdf" "$TMP/trunc-256.pdf"
expect_ok   "$QPDF" --show-npages --password="$long_pw"  "$TMP/trunc-256.pdf"
expect_fail "$QPDF" --show-npages --password="$other_pw" "$TMP/trunc-256.pdf"

expect_silent_ok "128-bit truncating write" "$QPDF" --encrypt --user-password="$long_pw" \
    --owner-password="$long_pw" --bits=128 --use-aes=y -- "$FIX/text.pdf" "$TMP/trunc-128.pdf"
expect_ok "$QPDF" --show-npages --password="$other_pw" "$TMP/trunc-128.pdf"
# The boundary is 32 exactly, not "32 or fewer". Without this line the pair
# above would also pass if the truncation happened at 20.
expect_fail "$QPDF" --show-npages --password="$near_pw" "$TMP/trunc-128.pdf"

# 40-bit truncates at 32 too, which is what its notice in the app claims.
#
# This is the only silence-asserted write carrying --allow-weak-crypto, and qpdf
# has been tightening weak crypto for several releases. So the likeliest reason
# this line ever goes non-silent is an RC4/40-bit deprecation notice rather than
# anything about the password - read the output before concluding the truncation
# story changed.
expect_silent_ok "40-bit truncating write" "$QPDF" --allow-weak-crypto --encrypt \
    --user-password="$long_pw" --owner-password="$long_pw" --bits=40 \
    -- "$FIX/text.pdf" "$TMP/trunc-40.pdf"
expect_ok   "$QPDF" --show-npages --password="$other_pw" "$TMP/trunc-40.pdf"
expect_fail "$QPDF" --show-npages --password="$near_pw"  "$TMP/trunc-40.pdf"

# --- the silent 127-byte cliff ---------------------------------------------
#
# AES-256 stores at most 127 bytes of password. At 128 qpdf writes the file,
# exits 0, says nothing, and the result cannot be reopened with the password
# that created it. QuickPDF refuses anything longer before writing; if qpdf ever
# starts reporting this itself, this case is how we find out the guard can go.
#
# "Says nothing" is asserted rather than assumed, and until it was, that promise
# was empty: every assertion covering an encrypt call read exit status only, so
# a qpdf that wrote the file, exited 0 and printed a warning about the length
# would have passed this file unchanged - which is precisely the change the
# guard is waiting for.
pw127="$(/usr/bin/python3 -c 'print("a"*127)')"
pw128="$(/usr/bin/python3 -c 'print("a"*128)')"

expect_ok "$QPDF" --encrypt --user-password="$pw127" --owner-password="$pw127" \
    --bits=256 -- "$FIX/text.pdf" "$TMP/len127.pdf"
expect_ok "$QPDF" --show-npages --password="$pw127" "$TMP/len127.pdf"

expect_silent_ok "over-length write past the 127-byte cliff" \
    "$QPDF" --encrypt --user-password="$pw128" --owner-password="$pw128" \
    --bits=256 -- "$FIX/text.pdf" "$TMP/len128.pdf"
expect_fail "$QPDF" --show-npages --password="$pw128" "$TMP/len128.pdf"

# --- 128-bit is RC4 unless asked otherwise ---------------------------------
#
# qpdf refuses to write RC4 without --allow-weak-crypto, so a 128-bit request
# that does not say --use-aes=y fails outright rather than quietly writing
# something weak. That refusal is what makes the app's --use-aes=y load-bearing.
expect_code 2 "$QPDF" --encrypt --user-password=pw \
    --owner-password=pw --bits=128 -- "$FIX/text.pdf" "$TMP/limits-rc4.pdf"
# ...and with the flag, the same request succeeds and really is AES.
expect_ok "$QPDF" --encrypt --user-password=pw --owner-password=pw \
    --bits=128 --use-aes=y -- "$FIX/text.pdf" "$TMP/limits-aes128.pdf"
expect_grep "R = 4" "$QPDF" --show-encryption --password=pw "$TMP/limits-aes128.pdf"
