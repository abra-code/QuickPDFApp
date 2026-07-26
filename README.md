# QuickPDF

A native macOS utility for everyday PDF tasks — optimize, split, merge, extract, rotate, encrypt, decrypt, repair, strip metadata, and flatten — driven by the [qpdf](https://github.com/qpdf/qpdf) engine with a Quartz-based image reducer for scanned documents. QuickPDF processes one file or a whole batch of files and folders in a single pass.

**Requires macOS 14.6 (Sonoma) or later.**

---

## Overview

QuickPDF presents a single window: pick an operation, adjust its options, add PDFs (or drop folders), and run. A built-in Quick Look preview lets you inspect any file in the list before processing.

Most operations are 1-in / 1-out transforms applied to every file in the list, writing results into a destination folder you choose (or, for a single file, a Save As path). Merge combines the list into one PDF; Split writes each input's parts into its own subfolder.

---

## Requirements

| Requirement | Notes |
|---|---|
| macOS 14.6+ | Sonoma minimum |
| No external dependencies | The qpdf and pdfutil engines are bundled in `Contents/Helpers/`; nothing to install |

---

## Operations

| Operation | What it does |
|---|---|
| **Optimize** | Reduce file size. Recompresses and downsamples images (via pdfutil's `reduce` verb), lossless stream compression, object-stream generation, removal of unreferenced resources, and optional linearization for fast web view (kept only if it does not grow the file). |
| **Split** | Split a PDF into parts of N pages each; parts land in a subfolder named after the source file. |
| **Extract Pages** | Extract or reorder a page range using qpdf's page-range syntax. |
| **Merge** | Combine every PDF in the list into one file, with an optional page range applied to each input. |
| **Set Password** | Encrypt with user and/or owner passwords, choosing 40-, 128-, or 256-bit encryption and per-permission flags (print, modify, extract, annotate). |
| **Decrypt** | Remove the password, or clear only the restrictions while keeping the file readable. |
| **Rotate Pages** | Rotate a page range by a chosen angle. |
| **Repair** | Rebuild the file structure; optionally coalesce content streams. |
| **Remove Metadata** | Strip XMP metadata, the document Info dictionary, structure tags, and/or page labels. |
| **Flatten** | Flatten annotations and form fields, optionally regenerating appearances first and flattening page rotation. |

---

## Optimizing scanned PDFs

qpdf performs excellent lossless structural optimization, but it cannot downsample images and silently skips images in ICC or JPEG (DCTDecode) colorspaces — exactly the images that dominate scanned documents. As a result, plain qpdf optimization often leaves a scanned PDF unchanged.

QuickPDF fills that gap with a bundled helper, **pdfutil**, whose `reduce` verb recompresses and downsamples images through the macOS Quartz image filter (the same engine behind Preview's "Reduce File Size"), regardless of colorspace. When "Recompress images" is enabled, Optimize runs a two-stage pipeline: `pdfutil reduce` handles the images, then qpdf does the structural pass.

- **JPEG quality** (default 85) controls image re-encoding.
- **Downsample images over N DPI** (default 150) is the primary size lever for scans; it is a ceiling, so images already below the threshold are left untouched and nothing is upscaled.

pdfutil's `reduce` redraws pages through a PDF context, so text and vector content stay selectable and sharp, but annotations, links, outlines, and form fields are not carried over. For that reason, leaving "Recompress images" off keeps the fully structure-preserving qpdf-only path. pdfutil is a general-purpose PDF tool developed separately; its source lives at [github.com/abra-code/pdfutil](https://github.com/abra-code/pdfutil).

---

## Bundled Helpers

| Helper | Location | Purpose |
|---|---|---|
| [qpdf](https://github.com/qpdf/qpdf) | `Contents/Helpers/qpdf` | Structural PDF engine for all operations (self-contained universal binary) |
| [pdfutil](https://github.com/abra-code/pdfutil) | `Contents/Helpers/pdfutil` | Quartz-based image recompression and downsampling for Optimize (its `reduce` verb) |

The bundled binaries are not committed to the repository (`Contents/Helpers/` is gitignored). `update_quickpdf.sh` builds both helpers universal, deploys them into the bundle, and re-signs the app:

```bash
./update_quickpdf.sh                 # rebuild pdfutil, reuse the embedded qpdf, ad-hoc sign
./update_quickpdf.sh --with-qpdf     # also rebuild the static qpdf from source
```

pdfutil is built from a sibling `../pdfutil` checkout (the script offers to clone it if missing) with its own `build.sh` (plain `swiftc`, system frameworks only). qpdf is built statically — no dylib dependencies — by the vendored wrapper in [`qpdf/`](qpdf/), which downloads and compiles zlib, libjpeg-turbo, OpenSSL, and qpdf itself. The qpdf build is opt-in via `--with-qpdf` (slow) but auto-enabled on a fresh checkout when no qpdf is embedded yet. See `./update_quickpdf.sh --help` for all options.

---

## Tests

`./test.sh` runs the cross-tool suite: the tests that only make sense here, where
both engines ship in one bundle and Optimize runs them as a pipeline.

```bash
./test.sh                                        # test this repo's QuickPDF.app
QUICKPDF_APP=/Applications/QuickPDF.app ./test.sh # test an installed bundle
```

Both helpers are **required** — they are the subject of the tests, so a missing
binary is a hard error rather than a skip. Run `./update_quickpdf.sh --with-qpdf`
first on a fresh checkout, since `Contents/Helpers/` is gitignored. Fixtures are
generated on first run by `Tests/make-fixtures.swift` (needs `swift`) and are
gitignored; only the generator is committed.

| Case | What it covers |
|---|---|
| `helpers.sh` | Both binaries universal, statically self-contained, signed. Includes a regression guard for the RC4 / `/R 2-4` capability that depends on OpenSSL's legacy provider being built into qpdf. |
| `encryption-interop.sh` | Each engine reads what the other writes, across 40-bit (`/R 2`), 128-bit (`/R 3`), and 256-bit (`/R 6`), plus pdfutil's `/R 4` AES-128 in the other direction. Also the permission reporting where the two tools genuinely disagree. |
| `structure.sh` | `qpdf --check` as an independent structural opinion on the output of every pdfutil verb, plus page-count and content agreement. |
| `optimize-pipeline.sh` | The app's real `build_qpdf_args` and `optimize_file`, sourced from `lib.QuickPDF.sh`, driven through `OMC_ACTIONUI_VIEW_*` state. Covers the two-stage scan reduction, the qpdf-only text path, linearize keep-if-smaller, and failure handling. |

Two known divergences are asserted rather than tolerated, so that a change in
either is noticed instead of silently absorbed:

- **PDFKit over-reports print permissions.** For a file whose `/P` denies
  high-resolution printing, qpdf reports it denied while pdfutil reports
  `high-quality-printing` as allowed. pdfutil faithfully reports PDFKit's
  `accessPermissions`, which conflates the two print bits.
- **PDFKit's linearizer writes an imperfect hint table.** `qpdf --check` on
  `pdfutil linearize` output exits 3 with shared-object hint warnings; the file is
  valid and genuinely linearized, and qpdf's own linearizer is clean.

## Architecture

QuickPDF is an OMC 5.1 applet. The OMC framework handles the app lifecycle, the operation window, file/folder dialogs, drag-and-drop, and Quick Look. The UI is defined declaratively in `QuickPDF.json` (and `QuickPDFQuickLook.json` for the preview window) in ActionUI format. All business logic runs as shell scripts in `Contents/Resources/Scripts/`, with shared functions and control-ID constants in `lib.QuickPDF.sh`.

Command routing is declared in `Contents/Resources/Command.json`: adding files, selection changes, running a single file (`QuickPDF.run.single.sh`), running a batch to a folder (`QuickPDF.run.batch.sh`), and merging (`QuickPDF.run.merge.sh`). `build_qpdf_args` in `lib.QuickPDF.sh` translates the current UI state into qpdf arguments for the selected operation.

---

## Building and Signing

The app bundle runs as-is once the helper binaries are in place. After changing scripts, UI JSON, or helpers, re-sign the bundle so the signature stays valid:

```bash
./codesign_applet.sh QuickPDF.app -                 # ad-hoc (local use)
./codesign_applet.sh QuickPDF.app "Developer ID Application: ..."   # for distribution
```

Developer ID signing enables the hardened runtime and a timestamp; for distribution the app should then be notarized with `xcrun notarytool`.

---

## License

QuickPDF is licensed under the Apache License 2.0 — see [LICENSE](LICENSE).

The bundled qpdf engine is copyright Jay Berkenbilt and Manfred Holger and is distributed under the Apache License 2.0 (with an Artistic License 2.0 option for older versions); see `Contents/Helpers/LICENSE.txt` and `Contents/Helpers/NOTICE.md`. The libraries statically linked into qpdf — zlib, libjpeg-turbo, and OpenSSL — ship their license texts beside it as `Contents/Helpers/zlib.LICENSE`, `libjpeg-turbo.LICENSE`, and `openssl.LICENSE`.

The bundled [pdfutil](https://github.com/abra-code/pdfutil) helper is distributed under the Apache License 2.0; its license text is included at `Contents/Helpers/pdfutil.LICENSE`.
