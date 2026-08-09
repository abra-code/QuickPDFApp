#!/usr/bin/env python3
"""Point a PDF's startxref at an offset that does not exist. For Tests/40-run.

    damage_startxref.py <file.pdf>

qpdf reacts by reconstructing the cross-reference table, printing WARNING lines,
and exiting 3 - "I recovered from something". That exit code is the point: it is
neither success nor failure, and QuickPDF.run.single has a branch for it that no
undamaged fixture can reach.

Damaging a copy at run time rather than committing a broken PDF keeps the
repository free of binary fixtures and makes the one property the test depends
on - which byte is wrong - readable instead of buried in a blob.

A file this could not damage is left untouched and reported, so the test fails
by saying the fixture is wrong rather than by asserting nothing.
"""
import sys


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: damage_startxref.py <file.pdf>\n")
        return 2
    path = argv[1]
    with open(path, "rb") as handle:
        data = handle.read()

    start = data.rfind(b"startxref")
    if start == -1:
        sys.stderr.write("damage_startxref.py: no startxref in %s\n" % path)
        return 1
    end = data.find(b"\n", start + len(b"startxref"))
    if end == -1:
        sys.stderr.write("damage_startxref.py: startxref has no newline after it\n")
        return 1

    with open(path, "wb") as handle:
        handle.write(data[:start + len(b"startxref")] + b"\n999999" + data[end:])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
