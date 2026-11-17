import AppKit
import CoreGraphics
import Foundation

@main
enum SVGCompare {
    static let canvasSize = 512

    static func usage() -> Never {
        fputs("Usage: svg-compare <image-a.png> <image-b.png>\n", stderr)
        exit(1)
    }

    static func fail(_ message: String) -> Never {
        fputs("Error: \(message)\n", stderr)
        exit(1)
    }

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 2 else {
            usage()
        }

        let leftURL = URL(fileURLWithPath: args[0])
        let rightURL = URL(fileURLWithPath: args[1])

        guard let leftImage = NSImage(contentsOf: leftURL),
              let rightImage = NSImage(contentsOf: rightURL) else {
            fail("failed to open input images")
        }

        guard let leftPixels = rasterizedPixels(for: leftImage),
              let rightPixels = rasterizedPixels(for: rightImage) else {
            fail("failed to rasterize input images")
        }

        guard leftPixels.count == rightPixels.count else {
            fail("pixel buffers mismatch")
        }

        var absTotal = 0.0
        for i in 0..<leftPixels.count {
            absTotal += abs(Double(leftPixels[i]) - Double(rightPixels[i]))
        }

        let mae = absTotal / Double(leftPixels.count)
        let similarity = max(0, min(1, 1 - (mae / 255.0)))
        let leftSize = resolvedSize(for: leftImage)
        let rightSize = resolvedSize(for: rightImage)

        print(
            String(
                format: "%.6f,%.6f,%d,%d,%d,%d",
                similarity,
                mae,
                Int(leftSize.width.rounded()),
                Int(leftSize.height.rounded()),
                Int(rightSize.width.rounded()),
                Int(rightSize.height.rounded())
            )
        )
    }

    static func resolvedSize(for image: NSImage) -> CGSize {
        if image.size.width > 0 && image.size.height > 0 {
            return image.size
        }
        for rep in image.representations {
            let width = rep.pixelsWide > 0 ? CGFloat(rep.pixelsWide) : rep.size.width
            let height = rep.pixelsHigh > 0 ? CGFloat(rep.pixelsHigh) : rep.size.height
            if width > 0 && height > 0 {
                return CGSize(width: width, height: height)
            }
        }
        return CGSize(width: 1, height: 1)
    }

    static func rasterizedPixels(for image: NSImage) -> [UInt8]? {
        let bytesPerPixel = 4
        let bytesPerRow = canvasSize * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: canvasSize * canvasSize * bytesPerPixel)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &pixels,
                  width: canvasSize,
                  height: canvasSize,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

        let drawRect = aspectFitRect(imageSize: resolvedSize(for: image), canvas: CGFloat(canvasSize))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        image.draw(
            in: drawRect,
            from: .zero,
            operation: .copy,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        NSGraphicsContext.restoreGraphicsState()
        return pixels
    }

    static func aspectFitRect(imageSize: CGSize, canvas: CGFloat) -> CGRect {
        let safeWidth = max(imageSize.width, 1)
        let safeHeight = max(imageSize.height, 1)
        let scale = min(canvas / safeWidth, canvas / safeHeight)
        let width = safeWidth * scale
        let height = safeHeight * scale
        let x = (canvas - width) / 2
        let y = (canvas - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
