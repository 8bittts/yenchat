import AppKit
import CoreGraphics
import Foundation

// Reports what a rendered thumbnail holds, for scripts/30-eval-svgthumb.sh.
// Prints "<width>,<height>,<drawn fraction>", where the drawn fraction is the
// share of pixels that are not fully transparent. A blank render scores 0.
@main
enum SVGInspect {
    static func fail(_ message: String) -> Never {
        fputs("Error: \(message)\n", stderr)
        exit(1)
    }

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 1 else {
            fputs("Usage: svg-inspect <image.png>\n", stderr)
            exit(1)
        }

        guard let image = NSImage(contentsOf: URL(fileURLWithPath: args[0])),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fail("failed to open image: \(args[0])")
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            fail("image has no pixels: \(args[0])")
        }

        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &pixels,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * bytesPerPixel,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            fail("failed to create a bitmap context")
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var drawn = 0
        for index in stride(from: bytesPerPixel - 1, to: pixels.count, by: bytesPerPixel) where pixels[index] != 0 {
            drawn += 1
        }

        print(String(format: "%d,%d,%.6f", width, height, Double(drawn) / Double(width * height)))
    }
}
