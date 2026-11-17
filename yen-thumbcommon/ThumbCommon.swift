import AppKit
import Foundation

// Shared helpers for the yen-*thumb native thumbnailers (pdf/svg/vid).
// Appended to each tool's swiftc invocation in its build.sh so usage/fail,
// PNG encoding, and output-dir-create+write live in one place and can't drift
// between the three tools (the vidthumb mkdir gap was that drift materialized).
enum ThumbCommon {
    static func fail(_ message: String) -> Never {
        fputs("Error: \(message)\n", stderr)
        exit(1)
    }

    static func usage(_ lines: [String]) -> Never {
        for line in lines {
            fputs(line, stderr)
        }
        exit(1)
    }

    static func encodePNG(cgImage: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    static func writeOutput(_ data: Data, to path: String) {
        let outputURL = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: outputURL)
        } catch {
            fail("failed to write output: \(error.localizedDescription)")
        }
    }
}
