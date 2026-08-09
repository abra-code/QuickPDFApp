#!/usr/bin/env python3
"""Which handlers end up reading the whole file list? For Tests/20-filelist.

    file_list_readers.py <scripts-dir> <env-var-name>

Prints one handler stem per line: every `<App>.*.sh` that reads the variable,
whether it names it directly or reaches it through a library function it calls.

Why not just grep the handler files. In these applets most handlers read the
list INDIRECTLY - PDFUtil.add.files never mentions the variable, it calls
add_files_to_table, which does. A grep of handler text therefore sees a minority
of the real readers, and the manifest cross-check built on it inspects a handful
of files while claiming to cover all of them. That was measured, not assumed: a
reviewer deleted one handler's ENVIRONMENT_VARIABLES block from Command.json and
the check stayed green.

Why not just "sources a library that mentions the variable" either. That is the
opposite error and is far too broad: every handler sources the core library, and
several source the files library for one unrelated helper, so nearly the whole
bundle comes back as a reader.

So the resolution is at FUNCTION level. Find the library functions whose own body
touches the variable, then find the handlers that call one of them. One level of
indirection is enough for these applets - a library function calling another
library function that reads the list would be missed, so that case is detected
and reported rather than silently dropped.
"""
import os
import re
import sys

FUNCTION_START = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{")


def functions_touching(path, needle):
    """Names of functions in `path` whose body contains `needle`."""
    found = set()
    current = None
    depth = 0
    with open(path, "r", errors="replace") as handle:
        for line in handle:
            if current is None:
                match = FUNCTION_START.match(line)
                if match:
                    current = match.group(1)
                    # The opening brace is on this line; count from here.
                    depth = line.count("{") - line.count("}")
                    if needle in line:
                        found.add(current)
                    if depth <= 0:
                        current = None
                continue
            if needle in line:
                found.add(current)
            depth += line.count("{") - line.count("}")
            if depth <= 0:
                current = None
    return found


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: file_list_readers.py <scripts-dir> <env-var-name>\n")
        return 2
    scripts_dir, needle = argv[1], argv[2]
    if not os.path.isdir(scripts_dir):
        sys.stderr.write("file_list_readers.py: no such directory %s\n" % scripts_dir)
        return 1

    names = sorted(n for n in os.listdir(scripts_dir) if n.endswith(".sh"))
    libs = [n for n in names if n.startswith("lib.")]
    handlers = [n for n in names if not n.startswith("lib.")]

    reading_functions = set()
    for lib in libs:
        reading_functions |= functions_touching(os.path.join(scripts_dir, lib), needle)

    # One level only. If a library function calls another library function that
    # reads the list, this would miss it - so say so rather than under-report in
    # silence.
    for lib in libs:
        path = os.path.join(scripts_dir, lib)
        for caller, callees in _calls_within(path).items():
            if caller in reading_functions:
                continue
            hit = callees & reading_functions
            if hit:
                sys.stderr.write(
                    "file_list_readers.py: %s() calls %s, which reads the list - "
                    "this resolver only follows one level, so extend it\n"
                    % (caller, ", ".join(sorted(hit))))

    if not reading_functions:
        sys.stderr.write(
            "file_list_readers.py: no library function reads %s - either the "
            "variable name is wrong or the applet changed shape\n" % needle)

    out = []
    for handler in handlers:
        path = os.path.join(scripts_dir, handler)
        with open(path, "r", errors="replace") as fh:
            body = fh.read()
        if needle in body or any(_calls(body, fn) for fn in reading_functions):
            out.append(handler[:-len(".sh")])

    sys.stdout.write("\n".join(sorted(out)))
    if out:
        sys.stdout.write("\n")
    return 0


def _calls(body, function_name):
    return re.search(r"(^|[^A-Za-z0-9_.])%s\b" % re.escape(function_name),
                     body, re.MULTILINE) is not None


def _calls_within(path):
    """function name -> set of other function-looking words it invokes."""
    calls = {}
    current = None
    depth = 0
    with open(path, "r", errors="replace") as handle:
        for line in handle:
            if current is None:
                match = FUNCTION_START.match(line)
                if match:
                    current = match.group(1)
                    calls.setdefault(current, set())
                    depth = line.count("{") - line.count("}")
                    if depth <= 0:
                        current = None
                continue
            for word in re.findall(r"(?:^|[^A-Za-z0-9_.$\"'])([a-z_][a-z0-9_]*)\s*(?:\n|;|\||&|$| )",
                                   line):
                calls[current].add(word)
            depth += line.count("{") - line.count("}")
            if depth <= 0:
                current = None
    return calls


if __name__ == "__main__":
    sys.exit(main(sys.argv))
