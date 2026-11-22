import AppKit
import Compression
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
        // An `.svgz` file is a gzip member around the SVG text. AppKit reads
        // only the plain form, so inflate it here and parse the bytes.
        var inflatedSVG: Data?
        if let handle = try? FileHandle(forReadingFrom: sourceURL) {
            let magic = (try? handle.read(upToCount: 2)) ?? Data()
            try? handle.close()
            if magic.elementsEqual([0x1F, 0x8B]) {
                guard let compressed = try? Data(contentsOf: sourceURL),
                      let inflated = gunzip(compressed) else {
                    fail("failed to decompress SVGZ: \(sourcePath)")
                }
                inflatedSVG = inflated
            }
        }

        let parsedImage: NSImage?
        if let inflatedSVG {
            parsedImage = NSImage(data: inflatedSVG)
        } else {
            parsedImage = NSImage(contentsOf: sourceURL)
        }
        guard let image = parsedImage else {
            fail("failed to parse SVG: \(sourcePath)")
        }

        let sourceText = inflatedSVG.map { String(decoding: $0, as: UTF8.self) }
            ?? (try? String(contentsOf: sourceURL, encoding: .utf8))
        let sourceSize = resolveSourceSize(image: image, sourceText: sourceText)
        let targetSize = scaledSize(from: sourceSize, maxDimension: maxDimension)
        guard let pngData = rasterize(image: image, targetSize: targetSize) else {
            fail("failed to rasterize SVG")
        }

        ThumbCommon.writeOutput(pngData, to: outputPath)
    }

    /// Largest SVG text an `.svgz` file may inflate to. DEFLATE can expand
    /// about a thousandfold, so the cap bounds memory for a hostile file.
    static let maxInflatedBytes = 64 * 1024 * 1024

    /// Inflates one gzip member (RFC 1952). Returns nil for a malformed
    /// header, a truncated stream, or output above `limit`.
    static func gunzip(_ data: Data, limit: Int = maxInflatedBytes) -> Data? {
        let bytes = [UInt8](data)
        // 10-byte header, at least one DEFLATE byte, 8-byte trailer.
        guard bytes.count > 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else {
            return nil
        }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 { // FEXTRA: two-byte little-endian length, then payload
            guard offset + 2 <= bytes.count else { return nil }
            offset += 2 + Int(bytes[offset]) + (Int(bytes[offset + 1]) << 8)
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 { // FNAME, FCOMMENT
            guard offset < bytes.count,
                  let end = bytes[offset...].firstIndex(of: 0) else { return nil }
            offset = end + 1
        }
        if flags & 0x02 != 0 { // FHCRC
            offset += 2
        }
        guard offset < bytes.count - 8 else { return nil }
        return inflate(Array(bytes[offset..<(bytes.count - 8)]), limit: limit)
    }

    /// Inflates a raw DEFLATE stream in bounded chunks.
    static func inflate(_ deflated: [UInt8], limit: Int) -> Data? {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            return nil
        }
        defer { compression_stream_destroy(stream) }

        let chunkSize = 64 * 1024
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        var output = Data()
        return deflated.withUnsafeBufferPointer { source -> Data? in
            guard let sourceBase = source.baseAddress else { return nil }
            stream.pointee.src_ptr = sourceBase
            stream.pointee.src_size = source.count
            while true {
                let (status, produced): (compression_status, Int) = chunk.withUnsafeMutableBufferPointer { destination in
                    guard let destinationBase = destination.baseAddress else {
                        return (COMPRESSION_STATUS_ERROR, 0)
                    }
                    stream.pointee.dst_ptr = destinationBase
                    stream.pointee.dst_size = chunkSize
                    let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                    return (status, chunkSize - stream.pointee.dst_size)
                }
                guard status != COMPRESSION_STATUS_ERROR else { return nil }
                output.append(contentsOf: chunk[0..<produced])
                guard output.count <= limit else { return nil }
                if status == COMPRESSION_STATUS_END {
                    return output
                }
                // No output and no input left means the stream stops short.
                if produced == 0, stream.pointee.src_size == 0 {
                    return nil
                }
            }
        }
    }

    static func resolveSourceSize(image: NSImage, sourceText: String?) -> CGSize {
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

        if let raw = sourceText,
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
