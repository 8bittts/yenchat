import AppKit
import Foundation

@main
enum SVGThumb {
    static func usage() -> Never {
        ThumbCommon.usage([
            "Usage: yen-svgthumb <svg> <output.png> [--max-dimension <px>]\n",
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

        let sourcePath = args[0]
        let outputPath = args[1]

        var maxDimension: CGFloat = 2000
        var index = 2
        while index < args.count {
            let flag = args[index]
            if flag == "--max-dimension" {
                guard index + 1 < args.count else {
                    usage()
                }
                guard let value = Int(args[index + 1]), value >= 64, value <= 8192 else {
                    fail("invalid --max-dimension (expected 64-8192): \(args[index + 1])")
                }
                maxDimension = CGFloat(value)
                index += 2
            } else {
                usage()
            }
        }

        guard FileManager.default.fileExists(atPath: sourcePath) else {
            fail("file not found: \(sourcePath)")
        }

        let sourceURL = URL(fileURLWithPath: sourcePath)
        guard let image = NSImage(contentsOf: sourceURL) else {
            fail("failed to parse SVG: \(sourcePath)")
        }

        let sourceSize = resolveSourceSize(image: image, sourceURL: sourceURL)
        let targetSize = scaledSize(from: sourceSize, maxDimension: maxDimension)
        guard let pngData = rasterize(image: image, targetSize: targetSize) else {
            fail("failed to rasterize SVG")
        }

        ThumbCommon.writeOutput(pngData, to: outputPath)
    }

    static func resolveSourceSize(image: NSImage, sourceURL: URL) -> CGSize {
        if let size = normalized(size: image.size) {
            return size
        }

        for rep in image.representations {
            let repSize = CGSize(
                width: rep.pixelsWide > 0 ? CGFloat(rep.pixelsWide) : rep.size.width,
                height: rep.pixelsHigh > 0 ? CGFloat(rep.pixelsHigh) : rep.size.height
            )
            if let size = normalized(size: repSize) {
                return size
            }
        }

        if let raw = try? String(contentsOf: sourceURL, encoding: .utf8),
           let tagRange = raw.range(of: "<svg[^>]*>", options: .regularExpression) {
            let header = String(raw[tagRange])
            if let viewBoxSize = parseViewBox(from: header),
               let size = normalized(size: viewBoxSize) {
                return size
            }
            let width = parseLength(attribute: "width", in: header)
            let height = parseLength(attribute: "height", in: header)
            if let width, let height,
               let size = normalized(size: CGSize(width: width, height: height)) {
                return size
            }
        }

        return CGSize(width: 1000, height: 1000)
    }

    static func parseViewBox(from header: String) -> CGSize? {
        let pattern = #"viewBox\s*=\s*["']\s*([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\s+([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\s+([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\s+([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\s*["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(header.startIndex..<header.endIndex, in: header)
        guard let match = regex.firstMatch(in: header, options: [], range: range),
              match.numberOfRanges >= 5,
              let widthRange = Range(match.range(at: 3), in: header),
              let heightRange = Range(match.range(at: 4), in: header),
              let width = Double(header[widthRange]),
              let height = Double(header[heightRange]) else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    static func parseLength(attribute: String, in header: String) -> CGFloat? {
        let pattern = #"\#(attribute)\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(header.startIndex..<header.endIndex, in: header)
        guard let match = regex.firstMatch(in: header, options: [], range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: header) else {
            return nil
        }

        let raw = header[valueRange]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if raw.hasSuffix("%") {
            return nil
        }

        let numericPattern = #"^[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?"#
        guard let numberRegex = try? NSRegularExpression(pattern: numericPattern),
              let numberMatch = numberRegex.firstMatch(
                  in: raw,
                  options: [],
                  range: NSRange(raw.startIndex..<raw.endIndex, in: raw)
              ),
              let numberRange = Range(numberMatch.range(at: 0), in: raw),
              let value = Double(raw[numberRange]) else {
            return nil
        }

        let unit = raw[numberRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let pixels: Double
        switch unit {
        case "", "px":
            pixels = value
        case "pt":
            pixels = value * 96.0 / 72.0
        case "pc":
            pixels = value * 16.0
        case "mm":
            pixels = value * 96.0 / 25.4
        case "cm":
            pixels = value * 96.0 / 2.54
        case "in":
            pixels = value * 96.0
        default:
            return nil
        }

        guard pixels.isFinite, pixels > 0 else {
            return nil
        }

        return CGFloat(pixels)
    }

    static func normalized(size: CGSize) -> CGSize? {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        return size
    }

    static func scaledSize(from sourceSize: CGSize, maxDimension: CGFloat) -> CGSize {
        let longest = max(sourceSize.width, sourceSize.height)
        guard longest > 0 else {
            return CGSize(width: maxDimension, height: maxDimension)
        }
        let scale = maxDimension / longest
        let width = max(1, (sourceSize.width * scale).rounded())
        let height = max(1, (sourceSize.height * scale).rounded())
        return CGSize(width: width, height: height)
    }

    static func rasterize(image: NSImage, targetSize: CGSize) -> Data? {
        let pixelWidth = Int(targetSize.width)
        let pixelHeight = Int(targetSize.height)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        bitmap.size = targetSize
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        NSColor.clear.set()
        NSBezierPath(rect: NSRect(origin: .zero, size: targetSize)).fill()

        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: .zero,
            operation: .copy,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }
}
