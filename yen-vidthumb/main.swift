import AVFoundation
import AppKit
import Foundation

// yen-vidthumb — native macOS video thumbnailer
// Replaces ffmpeg + ffprobe (~248MB) with a ~1MB binary using AVFoundation.
//
// Usage:
//   yen-vidthumb <video-path> <output-path> [--seek <seconds>] [--max-width <pixels>] [--max-height <pixels>]
//   yen-vidthumb <video-path> --duration

@main
enum VidThumb {
    static func usage() -> Never {
        ThumbCommon.usage([
            "Usage: yen-vidthumb <video> <output.png> [--seek <seconds>] [--max-width <pixels>] [--max-height <pixels>]\n",
            "       yen-vidthumb <video> --duration\n",
        ])
    }

    static func fail(_ message: String) -> Never {
        ThumbCommon.fail(message)
    }

    static func main() async {
        let args = CommandLine.arguments

        guard args.count >= 3 else {
            usage()
        }

        let videoPath = args[1]
        let videoURL = URL(fileURLWithPath: videoPath)

        guard FileManager.default.fileExists(atPath: videoPath) else {
            fail("file not found: \(videoPath)")
        }

        let asset = AVURLAsset(url: videoURL)

        // --duration mode: print duration in seconds and exit
        if args[2] == "--duration" {
            guard args.count == 3 else {
                usage()
            }
            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                print(String(format: "%.2f", seconds))
            } catch {
                fail("cannot read duration: \(error.localizedDescription)")
            }
            exit(0)
        }

        // Frame extraction mode
        let outputPath = args[2]

        var seekTime: Double = 1.0
        var maxWidth = 2000
        var maxHeight = 2000

        var index = 3
        while index < args.count {
            let flag = args[index]
            guard index + 1 < args.count else {
                usage()
            }

            let value = args[index + 1]
            switch flag {
            case "--seek":
                guard let seekVal = Double(value) else {
                    fail("invalid seek time: \(value)")
                }
                seekTime = max(0, seekVal)
            case "--max-width":
                guard let parsedWidth = Int(value), parsedWidth > 0 else {
                    fail("invalid max width: \(value)")
                }
                maxWidth = parsedWidth
            case "--max-height":
                guard let parsedHeight = Int(value), parsedHeight > 0 else {
                    fail("invalid max height: \(value)")
                }
                maxHeight = parsedHeight
            default:
                usage()
            }

            index += 2
        }

        // Clamp seek time to video duration so AVAssetImageGenerator
        // doesn't silently return the last frame for out-of-range times
        if let duration = try? await asset.load(.duration) {
            let durationSec = CMTimeGetSeconds(duration)
            if durationSec.isFinite && durationSec > 0 {
                seekTime = min(seekTime, durationSec)
            }
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: CGFloat(maxWidth), height: CGFloat(maxHeight))
        // Never return a frame BEFORE the seek point — the default 1s seek exists
        // to skip the black / fade-in / logo frame at t=0. Allow a small window after.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        let time = CMTime(seconds: seekTime, preferredTimescale: 600)

        do {
            let (cgImage, _) = try await generator.image(at: time)

            guard let pngData = ThumbCommon.encodePNG(cgImage: cgImage) else {
                fail("failed to encode PNG")
            }
            ThumbCommon.writeOutput(pngData, to: outputPath)
        } catch {
            fail(error.localizedDescription)
        }
    }
}
