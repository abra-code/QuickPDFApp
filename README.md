# QuickPDF

A native macOS utility for everyday PDF tasks — optimize, split, merge, extract, rotate, encrypt, decrypt, repair, strip metadata, and flatten — driven by the [qpdf](https://github.com/qpdf/qpdf) engine with a Quartz-based image reducer for scanned documents. QuickPDF processes one file or a whole batch of files and folders in a single pass.

**Requires macOS 14.6 (Sonoma) or later.**

---

## Overview

QuickPDF presents a single window: pick an operation, adjust its options, add PDFs (or drop folders), and run. A built-in Quick Look preview lets you inspect any file in the list before processing.

Most operations are 1-in / 1-out transforms applied to every file in the list, writing results into a destination folder you choose (or, for a single file, a Save As path). Merge combines the list into one PDF; Split writes each input's parts into its own subfolder.

QuickPDF is built on the [OMC](https://abracode.com) framework with an ActionUI declarative UI engine. The UI is defined in `Contents/Resources/Base.lproj/QuickPDF.json`; all logic runs as shell scripts in `Contents/Resources/Scripts/`, communicating with the window in real time through the OMC dialog control tool.

---

## Requirements

| Requirement | Notes |
|---|---|
| macOS 14.6+ | Sonoma minimum |
| No external dependencies | The qpdf and pdfreduce engines are bundled in `Contents/Helpers/`; nothing to install |

---

## Operations

| Operation | What it does |
|---|---|
| **Optimize** | Reduce file size. Recompresses and downsamples images (via the pdfreduce helper), lossless stream compression, object-stream generation, removal of unreferenced resources, and optional linearization for fast web view (kept only if it does not grow the file). |
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

QuickPDF fills that gap with a small bundled helper, **pdfreduce**, which recompresses and downsamples images through the macOS Quartz image filter (the same engine behind Preview's "Reduce File Size"), regardless of colorspace. When "Recompress images" is enabled, Optimize runs a two-stage pipeline: pdfreduce handles the images, then qpdf does the structural pass.

- **JPEG quality** (default 85) controls image re-encoding.
- **Downsample images over N DPI** (default 150) is the primary size lever for scans; it is a ceiling, so images already below the threshold are left untouched and nothing is upscaled.

pdfreduce redraws pages through a PDF context, so text and vector content stay selectable and sharp, but annotations, links, outlines, and form fields are not carried over. For that reason, leaving "Recompress images" off keeps the fully structure-preserving qpdf-only path. The pdfreduce source is in [`Tools/pdfreduce/`](Tools/pdfreduce/).

---

## Bundled Helpers

| Helper | Location | Purpose |
|---|---|---|
| [qpdf](https://github.com/qpdf/qpdf) | `Contents/Helpers/qpdf` | Structural PDF engine for all operations (universal binary) |
| pdfreduce | `Contents/Helpers/pdfreduce` | Quartz-based image recompression and downsampling for Optimize; source in `Tools/pdfreduce/` |

The bundled binaries are not committed to the repository (`Contents/Helpers/` is gitignored). Build pdfreduce and install it into the app with:

```bash
./Tools/pdfreduce/build.sh QuickPDF.app
```

qpdf can be installed from a [qpdf release](https://github.com/qpdf/qpdf/releases) or built from source; place the universal `qpdf` binary in `Contents/Helpers/`.

---

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

The bundled qpdf engine is copyright Jay Berkenbilt and Manfred Holger and is distributed under the Apache License 2.0 (with an Artistic License 2.0 option for older versions); see `Contents/Helpers/LICENSE.txt` and `Contents/Helpers/NOTICE.md`.
