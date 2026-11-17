import AppKit
import CoreGraphics
import Foundation
import PDFKit

// yen-pdfthumb fixture generator — reviewable Swift source that emits the small
// binary PDF corpus the eval/soak harness consumes. Mirrors the yen-svgthumb
// pattern of building an auxiliary swiftc tool at runtime; here the tool
// GENERATES fixtures (there is no reference renderer to compare against, so the
// eval is self-validating). Fixtures are gitignored; only this generator plus
// fixtures/manifest.csv are committed.
//
// Usage: pdf-make-fixtures <output-dir>
//
// Emits (matching fixtures/manifest.csv):
//   multipage.pdf       3 landscape pages (~800x600pt), no rotation/encryption
//   portrait.pdf        1 portrait page (600x800pt)
//   rotated.pdf         1 landscape page (800x600pt) with page.rotation = 90
//                       so it DISPLAYS portrait (proves rotation handling)
//   encrypted-owner.pdf owner password set, EMPTY user password — opens via
//                       unlock("") (proves empty-password unlock renders)
//   encrypted-user.pdf  user password "secret" — unlock("") fails, helper exits
//                       non-zero (expected_failure)
@main
enum PDFMakeFixtures {
    static func fail(_ message: String) -> Never {
        fputs("Error: \(message)\n", stderr)
        exit(1)
    }

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 1 else {
            fputs("Usage: pdf-make-fixtures <output-dir>\n", stderr)
            exit(1)
        }

        let outDir = args[0]
        do {
            try FileManager.default.createDirectory(
                atPath: outDir,
                withIntermediateDirectories: true
            )
        } catch {
            fail("failed to create output dir: \(error.localizedDescription)")
        }

        let landscape = CGSize(width: 800, height: 600)
        let portrait = CGSize(width: 600, height: 800)

        // multipage.pdf — 3 landscape pages, distinct fill per page.
        let colors: [CGColor] = [
            CGColor(srgbRed: 0.85, green: 0.30, blue: 0.30, alpha: 1),
            CGColor(srgbRed: 0.30, green: 0.65, blue: 0.85, alpha: 1),
            CGColor(srgbRed: 0.40, green: 0.75, blue: 0.40, alpha: 1),
        ]
        writePDF(
            to: url(outDir, "multipage.pdf"),
            pages: colors.map { (landscape, $0) }
        )

        // portrait.pdf — single portrait page.
        writePDF(
            to: url(outDir, "portrait.pdf"),
            pages: [(portrait, CGColor(srgbRed: 0.55, green: 0.45, blue: 0.80, alpha: 1))]
        )

        // rotated.pdf — landscape media box rotated 90° so it displays portrait.
        let rotatedBase = url(outDir, "rotated.pdf")
        writePDF(
            to: rotatedBase,
            pages: [(landscape, CGColor(srgbRed: 0.90, green: 0.60, blue: 0.20, alpha: 1))]
        )
        applyRotation(to: rotatedBase, degrees: 90)

        // encrypted-owner.pdf — owner password only, empty user password.
        let ownerBase = url(outDir, "encrypted-owner.pdf")
        writePDF(
            to: ownerBase,
            pages: [(landscape, CGColor(srgbRed: 0.20, green: 0.55, blue: 0.60, alpha: 1))]
        )
        encrypt(ownerBase, options: [.ownerPasswordOption: "owner"])

        // encrypted-user.pdf — user password "secret" so unlock("") fails.
        let userBase = url(outDir, "encrypted-user.pdf")
        writePDF(
            to: userBase,
            pages: [(landscape, CGColor(srgbRed: 0.60, green: 0.20, blue: 0.35, alpha: 1))]
        )
        encrypt(userBase, options: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"])

        print("wrote fixtures to \(outDir)")
    }

    static func url(_ dir: String, _ name: String) -> URL {
        URL(fileURLWithPath: dir).appendingPathComponent(name)
    }

    // Render solid-color pages via a CGContext PDF context. Each page gets its
    // own media box so multi-page and single-page fixtures share one path.
    static func writePDF(to output: URL, pages: [(size: CGSize, color: CGColor)]) {
        try? FileManager.default.removeItem(at: output)
        guard let ctx = CGContext(output as CFURL, mediaBox: nil, nil) else {
            fail("failed to open PDF context: \(output.path)")
        }
        for page in pages {
            var box = CGRect(origin: .zero, size: page.size)
            ctx.beginPage(mediaBox: &box)
            ctx.setFillColor(page.color)
            ctx.fill(box)
            // A contrasting inset rectangle so the raster is not a flat field
            // (helps any visual spot-check of the generated thumbnails).
            let inset = box.insetBy(dx: page.size.width * 0.15, dy: page.size.height * 0.15)
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(inset)
            ctx.endPage()
        }
        ctx.closePDF()
    }

    // Load a generated PDF, rotate every page, and rewrite in place.
    static func applyRotation(to output: URL, degrees: Int) {
        guard let document = PDFDocument(url: output) else {
            fail("failed to reopen for rotation: \(output.path)")
        }
        for index in 0..<document.pageCount {
            document.page(at: index)?.rotation = degrees
        }
        guard document.write(to: output) else {
            fail("failed to rewrite rotated PDF: \(output.path)")
        }
    }

    // Load a generated PDF and rewrite it encrypted with the given options.
    static func encrypt(_ output: URL, options: [PDFDocumentWriteOption: Any]) {
        guard let document = PDFDocument(url: output) else {
            fail("failed to reopen for encryption: \(output.path)")
        }
        guard document.write(to: output, withOptions: options) else {
            fail("failed to write encrypted PDF: \(output.path)")
        }
    }
}
