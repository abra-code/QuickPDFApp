// make-fixtures.swift - generate the PDF fixtures the cross-tool test suite needs.
// Run with the Swift interpreter:
//
//     swift Tests/make-fixtures.swift Tests/fixtures
//
// Fixtures are gitignored; only this generator is committed, so every run
// regenerates them.
//
// They are NOT byte-reproducible: both CGContext.closePDF() and
// PDFDocument.write(to:) stamp a creation and modification date, so two runs a
// second apart differ byte for byte at identical sizes. Nothing checksums a
// fixture, and every assertion is about content rather than bytes, so this only
// matters if someone later tries to cache or diff them.
//
// Adapted from the generator in the pdfutil repo, trimmed to what the cross-tool
// cases here actually exercise: a text document, an image-only "scan" for the
// Optimize pipeline, and a filled form for the flatten comparison.

import Foundation
import PDFKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift make-fixtures.swift <outdir>\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func out(_ name: String) -> URL { outDir.appendingPathComponent(name) }

let letter = CGRect(x: 0, y: 0, width: 612, height: 792)

// Draw a single CoreText line at a baseline point.
func drawLine(_ ctx: CGContext, _ text: String, x: CGFloat, y: CGFloat, size: CGFloat) {
    let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
    let attributed = NSAttributedString(string: text, attributes: [.font: font])
    let line = CTLineCreateWithAttributedString(attributed)
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
}

// text.pdf - 5 pages, one marker plus one sentence each. Used for page-count and
// text-layer agreement between the tools, and as the encryption round-trip input.
do {
    var box = letter
    guard let ctx = CGContext(out("text.pdf") as CFURL, mediaBox: &box, nil) else {
        fatalError("cannot create text.pdf")
    }
    let sentences = [
        "The quick brown fox jumps over the lazy dog.",
        "Sphinx of black quartz, judge my vow.",
        "This page hides a needle in the haystack.",
        "Pack my box with five dozen liquor jugs.",
        "How vexingly quick daft zebras jump.",
    ]
    for p in 0..<5 {
        ctx.beginPDFPage(nil)
        drawLine(ctx, "PAGE-\(p + 1)-MARKER", x: 72, y: 700, size: 24)
        drawLine(ctx, sentences[p], x: 72, y: 650, size: 18)
        ctx.endPDFPage()
    }
    ctx.closePDF()
}

// scan.pdf - 2 image-only pages simulating a 200 dpi scan (1700x2200 on Letter),
// with no text layer, and with the images stored as JPEG (DCTDecode).
//
// The DCTDecode part is essential, not incidental. The whole reason QuickPDF
// bundles pdfutil is that qpdf will not downsample and skips DCTDecode/ICC images,
// so plain qpdf optimization leaves a real scan almost untouched. If this fixture
// stored its images as Flate instead, qpdf's --recompress-flate would shrink it on
// its own (measured: to ~57%) and the Optimize case would be testing nothing about
// why the two-engine pipeline exists. With DCTDecode, qpdf-only leaves it at ~99%
// while the reduce stage brings it to ~39%.
//
// Passing a JPEG through requires building the raster, encoding it to JPEG in
// memory, and reloading the CGImage from that JPEG data: a CGImage drawn straight
// from a bitmap context is re-encoded as Flate by the PDF context, whereas a
// JPEG-backed one is passed through as DCTDecode. The optimize case asserts the
// filter is really DCTDecode, so this does not silently regress.
do {
    func jpegRaster(_ text: String) -> CGImage {
        let width = 1700, height = 2200
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let bitmap = CGContext(data: nil, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            fatalError("cannot create bitmap context")
        }
        bitmap.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        drawLine(bitmap, text, x: 120, y: 2000, size: 64)
        // A gradient wedge gives the encoder real content to work on; a blank page
        // would compress to near nothing either way and prove little.
        for i in 0..<40 {
            let g = CGFloat(i) / 40.0
            bitmap.setFillColor(CGColor(red: g, green: 1 - g, blue: 0.5, alpha: 1))
            bitmap.fill(CGRect(x: 120 + i * 36, y: 400, width: 36, height: 1200))
        }
        guard let raw = bitmap.makeImage() else { fatalError("makeImage failed") }

        let jpeg = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
                jpeg, UTType.jpeg.identifier as CFString, 1, nil) else {
            fatalError("cannot create JPEG destination")
        }
        CGImageDestinationAddImage(dest, raw,
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { fatalError("JPEG encode failed") }
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            fatalError("cannot reload the JPEG")
        }
        return image
    }
    var box = letter
    guard let ctx = CGContext(out("scan.pdf") as CFURL, mediaBox: &box, nil) else {
        fatalError("cannot create scan.pdf")
    }
    for text in ["SCAN PAGE ONE", "SCAN PAGE TWO"] {
        ctx.beginPDFPage(nil)
        ctx.draw(jpegRaster(text), in: letter)
        ctx.endPDFPage()
    }
    ctx.closePDF()
}

// form-filled.pdf - one page with the "name" text field pre-filled ("Alice"), so
// the flatten comparison can confirm the value burns into the page content and
// the interactive widget is gone afterwards.
do {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
        fatalError("cannot create data consumer")
    }
    var box = letter
    guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
        fatalError("cannot create form base context")
    }
    ctx.beginPDFPage(nil)
    drawLine(ctx, "Filled form fixture", x: 72, y: 720, size: 18)
    ctx.endPDFPage()
    ctx.closePDF()

    guard let doc = PDFDocument(data: data as Data), let page = doc.page(at: 0) else {
        fatalError("cannot build filled-form base document")
    }
    let name = PDFAnnotation(bounds: CGRect(x: 72, y: 600, width: 200, height: 24),
                             forType: .widget, withProperties: nil)
    name.widgetFieldType = .text
    name.fieldName = "name"
    name.widgetStringValue = "Alice"
    page.addAnnotation(name)

    doc.write(to: out("form-filled.pdf"))
}

// outlined.pdf - three pages carrying a real document outline, and nothing else
// of interest. The Optimize structure pre-flight reports an outline separately
// from annotations, and no other fixture has one, so without this the "outline"
// branch of pdf_structure_at_risk would never be exercised.
do {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
        fatalError("cannot create data consumer")
    }
    var box = letter
    guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
        fatalError("cannot create outline base context")
    }
    for i in 1...3 {
        ctx.beginPDFPage(nil)
        drawLine(ctx, "Chapter \(i)", x: 72, y: 720, size: 18)
        ctx.endPDFPage()
    }
    ctx.closePDF()

    guard let doc = PDFDocument(data: data as Data) else {
        fatalError("cannot build outlined base document")
    }
    let root = PDFOutline()
    for i in 0..<3 {
        guard let page = doc.page(at: i) else { continue }
        let item = PDFOutline()
        item.label = "Chapter \(i + 1)"
        item.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: 792))
        root.insertChild(item, at: i)
    }
    doc.outlineRoot = root
    doc.write(to: out("outlined.pdf"))
}

FileHandle.standardError.write(Data("fixtures written to \(outDir.path)\n".utf8))
