// pdfreduce - shrink a PDF by recompressing/downsampling its images.
//
// Uses the macOS Quartz image filter (public QuartzFilter API) applied to a
// CGPDFContext. Text and vector content are re-recorded as text/vectors; only
// raster image XObjects are re-encoded and (optionally) downsampled. This
// handles ICC-profiled and already-JPEG images that qpdf's --optimize-images
// refuses to touch.
//
// Built as a universal (x86_64 + arm64) command-line helper that ships in
// QuickPDF.app/Contents/Helpers alongside qpdf.

import Foundation
import CoreGraphics
import Quartz

let argv = CommandLine.arguments
let prog = (argv.first.map { ($0 as NSString).lastPathComponent }) ?? "pdfreduce"

func die(_ msg: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(code)
}

func usage() -> Never {
    print("""
    Usage: \(prog) [options] <input.pdf> <output.pdf>

    Recompresses (and optionally downsamples) the images inside a PDF using the
    macOS Quartz image filter. Text and vector content are preserved; only raster
    images are re-encoded. Handles ICC/JPEG images that qpdf cannot optimize.

    Options:
      -q, --quality N   JPEG quality 1-100 (default 85)
      -r, --dpi N       Downsample images above this resolution, in DPI
                        (default 150; 0 disables resolution downsampling)
      -m, --max-edge N  Cap the longest image edge to N pixels (default 0 = no cap)
      -h, --help        Show this help

    Exit status: 0 success, 1 usage/argument error, 2 processing error.

    Note: pages are redrawn through a new PDF context, so annotations, links,
    outlines, and form fields are not carried over. Use the qpdf-based optimize
    for structure-preserving optimization of non-scanned PDFs.
    """)
    exit(0)
}

var quality = 85
var dpi = 150
var maxEdge = 0
var positional: [String] = []

var i = 1
while i < argv.count {
    let a = argv[i]
    func intArg(_ name: String) -> Int {
        i += 1
        guard i < argv.count, let v = Int(argv[i]) else { die("\(prog): \(name) requires an integer") }
        return v
    }
    switch a {
    case "-h", "--help": usage()
    case "-q", "--quality": quality = intArg(a)
    case "-r", "--dpi": dpi = intArg(a)
    case "-m", "--max-edge": maxEdge = intArg(a)
    case "--":
        // Everything after "--" is positional, even if it starts with "-".
        positional.append(contentsOf: argv[(i + 1)...])
        i = argv.count
    default:
        if a.hasPrefix("-") && a != "-" { die("\(prog): unknown option '\(a)'") }
        positional.append(a)
    }
    i += 1
}

guard positional.count == 2 else {
    die("\(prog): expected <input.pdf> <output.pdf>\nTry '\(prog) --help'.")
}
let inPath = positional[0]
let outPath = positional[1]

// Clamp to sane ranges (mirrors the app's 1-100 JPEG quality slider).
quality = min(100, max(1, quality))
dpi = max(0, dpi)
maxEdge = max(0, maxEdge)

let inURL = URL(fileURLWithPath: inPath)
let outURL = URL(fileURLWithPath: outPath)

if inURL.standardizedFileURL == outURL.standardizedFileURL {
    die("\(prog): input and output must be different files", 1)
}
guard FileManager.default.fileExists(atPath: inPath) else {
    die("\(prog): input not found: \(inPath)", 2)
}
guard let doc = CGPDFDocument(inURL as CFURL) else {
    die("\(prog): cannot open PDF: \(inPath)", 2)
}
// A password-protected PDF opens as a non-nil but locked document that reports
// zero pages; report that accurately rather than "no pages".
if doc.isEncrypted && !doc.isUnlocked {
    die("\(prog): PDF is password-protected: \(inPath)", 2)
}
let pageCount = doc.numberOfPages
guard pageCount > 0 else { die("\(prog): PDF has no pages: \(inPath)", 2) }

// Build the Quartz filter properties at runtime - same schema as a .qfilter
// plist, but no temp file needed.
var imageScale: [String: Any] = ["ImageScaleInterpolate": true, "ImageSizeMin": 0]
if dpi > 0 { imageScale["ImageResolution"] = dpi }
if maxEdge > 0 { imageScale["ImageSizeMax"] = maxEdge }

let props: [String: Any] = [
    "Name": "QuickPDF Reduce",
    "FilterType": 1,
    "Domains": ["Applications": true, "Printing": true],
    "FilterData": ["ColorSettings": ["ImageSettings": [
        "ImageCompression": "ImageJPEGCompress",
        "Compression Quality": Double(quality) / 100.0,
        "ImageScaleSettings": imageScale,
    ]]],
]

guard let filter = QuartzFilter(properties: props) else {
    die("\(prog): failed to create Quartz filter", 2)
}

// Default context media box (per-page boxes are set in the loop).
var defaultBox = doc.page(at: 1)?.getBoxRect(.mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
guard let ctx = CGContext(outURL as CFURL, mediaBox: &defaultBox, nil) else {
    die("\(prog): cannot create output PDF: \(outPath)", 2)
}

filter.apply(to: ctx)

for p in 1...pageCount {
    // A page we counted but can't read means a corrupt/partial input; fail
    // loudly rather than silently emitting a PDF with fewer pages.
    guard let page = doc.page(at: p) else {
        die("\(prog): cannot read page \(p) of \(inPath)", 2)
    }
    var mediaBox = page.getBoxRect(.mediaBox)
    var cropBox = page.getBoxRect(.cropBox)
    let rotation = page.rotationAngle

    // Draw the page in its native (un-rotated) orientation. A rotation baked
    // into the CTM disables the Quartz filter's image downsampling, so instead
    // of transforming the content we preserve the page's /Rotate entry and let
    // the viewer rotate it. This keeps both the reduction and the orientation.
    var pageInfo: [String: Any] = [
        kCGPDFContextMediaBox as String: NSData(bytes: &mediaBox, length: MemoryLayout<CGRect>.size),
    ]
    // Preserve a distinct crop box (common on scans / press PDFs); otherwise the
    // output would reveal the full media box.
    if cropBox != mediaBox {
        pageInfo[kCGPDFContextCropBox as String] =
            NSData(bytes: &cropBox, length: MemoryLayout<CGRect>.size)
    }
    if rotation % 360 != 0 {
        // "Rotate" is an undocumented-but-honored CGPDFContext page key. If a
        // future macOS ignored it, the page would simply render un-rotated.
        pageInfo["Rotate"] = rotation
    }
    ctx.beginPDFPage(pageInfo as CFDictionary)
    ctx.drawPDFPage(page)
    ctx.endPDFPage()
}

filter.remove(from: ctx)
ctx.closePDF()

func fileSize(_ path: String) -> Int {
    guard let a = try? FileManager.default.attributesOfItem(atPath: path),
          let n = a[.size] as? Int else { return 0 }
    return n
}
let inSize = fileSize(inPath)
let outSize = fileSize(outPath)
let pct = inSize > 0 ? (1.0 - Double(outSize) / Double(inSize)) * 100.0 : 0
FileHandle.standardError.write(Data(
    String(format: "%@: %d page(s), %d -> %d bytes (%.1f%% smaller)\n",
           prog, pageCount, inSize, outSize, pct).utf8))
exit(0)
