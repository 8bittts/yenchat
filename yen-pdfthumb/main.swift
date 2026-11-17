import AppKit
import Foundation
import PDFKit

@main
enum PDFThumb {
    static func usage() -> Never {
        ThumbCommon.usage([
            "Usage: yen-pdfthumb <pdf> <output.png> [--page <n>] [--max-width <pixels>] [--max-height <pixels>]\n",
            "       yen-pdfthumb <pdf> --pages\n",
        ])
    }

    static func fail(_ message: String) -> Never {
        ThumbCommon.fail(message)
    }

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 2 else {
            usage()
        }

        let pdfPath = args[0]
        guard FileManager.default.fileExists(atPath: pdfPath) else {
            fail("file not found: \(pdfPath)")
        }

        let pdfURL = URL(fileURLWithPath: pdfPath)
        guard let document = PDFDocument(url: pdfURL) else {
            fail("failed to open PDF: \(pdfPath)")
        }

        if document.isEncrypted && !document.unlock(withPassword: "") {
            fail("PDF is encrypted and cannot be unlocked")
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else {
            fail("PDF has no pages")
        }

        if args[1] == "--pages" {
            guard args.count == 2 else {
                usage()
            }
            print(pageCount)
            exit(0)
        }

        let outputPath = args[1]
        var pageIndex = 0
        var maxWidth = 2000
        var maxHeight = 2000

        var index = 2
        while index < args.count {
            let flag = args[index]
            if flag == "--page" {
                guard index + 1 < args.count else {
                    usage()
                }
                guard let parsedPage = Int(args[index + 1]), parsedPage >= 0 else {
                    fail("invalid page index: \(args[index + 1])")
                }
                pageIndex = parsedPage
                index += 2
            } else if flag == "--max-width" {
                guard index + 1 < args.count else {
                    usage()
                }
                guard let parsedWidth = Int(args[index + 1]), parsedWidth > 0 else {
                    fail("invalid max width: \(args[index + 1])")
                }
                maxWidth = parsedWidth
                index += 2
            } else if flag == "--max-height" {
                guard index + 1 < args.count else {
                    usage()
                }
                guard let parsedHeight = Int(args[index + 1]), parsedHeight > 0 else {
                    fail("invalid max height: \(args[index + 1])")
                }
                maxHeight = parsedHeight
                index += 2
            } else {
                usage()
            }
        }

        guard pageIndex < pageCount else {
            fail("page index out of range: \(pageIndex) (pages: \(pageCount))")
        }

        guard let page = document.page(at: pageIndex) else {
            fail("failed to read page at index \(pageIndex)")
        }

        let image = page.thumbnail(of: CGSize(width: CGFloat(maxWidth), height: CGFloat(maxHeight)), for: .mediaBox)
        // Encode straight from the CGImage instead of round-tripping the NSImage
        // through a transient TIFF buffer (~32 MB per invocation in the yazi
        // PDF-preview hot path).
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fail("failed to encode PNG")
        }
        guard let pngData = ThumbCommon.encodePNG(cgImage: cgImage) else {
            fail("failed to encode PNG")
        }

        ThumbCommon.writeOutput(pngData, to: outputPath)
    }
}
