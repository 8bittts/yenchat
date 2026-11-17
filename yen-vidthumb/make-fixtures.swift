import AVFoundation
import AppKit
import CoreMedia
import CoreVideo
import Foundation

// yen-vidthumb fixture generator — reviewable Swift source that emits the small
// binary video corpus the eval/soak harness consumes. Mirrors the yen-svgthumb
// pattern of building an auxiliary swiftc tool at runtime; here the tool
// GENERATES fixtures (there is no reference renderer — ffmpeg/ffprobe were
// removed — so the eval is self-validating). Fixtures are gitignored; only this
// generator plus fixtures/manifest.csv are committed.
//
// Native dims are encoded LARGER than the eval cap because
// AVAssetImageGenerator.maximumSize only DOWNSCALES; a downscale must be
// observable for the dimension assertions to mean anything.
//
// Usage: vid-make-fixtures <output-dir>
//
// Emits (matching fixtures/manifest.csv):
//   landscape.mp4   1280x720 upright solid color (render_ok landscape baseline)
//   portrait.mp4    720x1280 upright solid color (render_ok portrait)
//   rotated.mp4     1280x720 with a 90° preferred transform so the helper (which
//                   applies preferredTrackTransform) yields PORTRAIT output
//   audio-only.m4a  AAC audio, no video track — generator.image throws, helper
//                   exits non-zero (expected_failure)
@main
enum VidMakeFixtures {
    static let fps: Int32 = 30
    static let durationSeconds = 1.5

    static func fail(_ message: String) -> Never {
        fputs("Error: \(message)\n", stderr)
        exit(1)
    }

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 1 else {
            fputs("Usage: vid-make-fixtures <output-dir>\n", stderr)
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

        await writeVideo(
            to: url(outDir, "landscape.mp4"),
            width: 1280, height: 720,
            transform: .identity,
            color: (200, 70, 70)
        )
        await writeVideo(
            to: url(outDir, "portrait.mp4"),
            width: 720, height: 1280,
            transform: .identity,
            color: (70, 160, 90)
        )
        // Encode landscape but tag a 90° preferred transform. With the helper's
        // appliesPreferredTrackTransform=true the presented frame is portrait.
        await writeVideo(
            to: url(outDir, "rotated.mp4"),
            width: 1280, height: 720,
            transform: CGAffineTransform(rotationAngle: .pi / 2),
            color: (70, 110, 200)
        )
        await writeAudioOnly(to: url(outDir, "audio-only.m4a"))

        print("wrote fixtures to \(outDir)")
    }

    static func url(_ dir: String, _ name: String) -> URL {
        URL(fileURLWithPath: dir).appendingPathComponent(name)
    }

    // Encode a solid-color H.264 clip. A single solid pixel buffer is reused for
    // every frame — the content only needs to be a decodable, non-empty video.
    static func writeVideo(
        to output: URL,
        width: Int,
        height: Int,
        transform: CGAffineTransform,
        color: (r: UInt8, g: UInt8, b: UInt8)
    ) async {
        try? FileManager.default.removeItem(at: output)

        guard let writer = try? AVAssetWriter(outputURL: output, fileType: .mp4) else {
            fail("failed to create writer: \(output.path)")
        }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        input.transform = transform

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attrs
        )

        guard writer.canAdd(input) else {
            fail("cannot add video input: \(output.path)")
        }
        writer.add(input)

        guard writer.startWriting() else {
            fail("startWriting failed: \(writer.error?.localizedDescription ?? "unknown")")
        }
        writer.startSession(atSourceTime: .zero)

        guard let buffer = solidPixelBuffer(width: width, height: height, color: color) else {
            fail("failed to allocate pixel buffer")
        }

        let totalFrames = Int(durationSeconds * Double(fps))
        for frame in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            let pts = CMTime(value: Int64(frame), timescale: fps)
            if !adaptor.append(buffer, withPresentationTime: pts) {
                fail("failed to append frame \(frame): \(writer.error?.localizedDescription ?? "unknown")")
            }
        }

        input.markAsFinished()
        await finish(writer)
    }

    // Solid-color 32ARGB pixel buffer (byte order A,R,G,B).
    static func solidPixelBuffer(
        width: Int,
        height: Int,
        color: (r: UInt8, g: UInt8, b: UInt8)
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width {
                let offset = row + x * 4
                ptr[offset + 0] = 255
                ptr[offset + 1] = color.r
                ptr[offset + 2] = color.g
                ptr[offset + 3] = color.b
            }
        }
        return buffer
    }

    // AAC-only .m4a: no video track, so the helper's generator.image throws.
    static func writeAudioOnly(to output: URL) async {
        try? FileManager.default.removeItem(at: output)

        guard let writer = try? AVAssetWriter(outputURL: output, fileType: .m4a) else {
            fail("failed to create audio writer: \(output.path)")
        }

        let sampleRate = 44100.0
        let channels = 1
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 64000,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        guard writer.canAdd(input) else {
            fail("cannot add audio input: \(output.path)")
        }
        writer.add(input)

        guard writer.startWriting() else {
            fail("startWriting failed (audio): \(writer.error?.localizedDescription ?? "unknown")")
        }
        writer.startSession(atSourceTime: .zero)

        // Feed silent LPCM sample buffers in chunks; the input's AAC output
        // settings encode them to AAC.
        let framesPerChunk = 4410
        let totalFrames = Int(durationSeconds * sampleRate)
        var startFrame = 0
        while startFrame < totalFrames {
            let count = min(framesPerChunk, totalFrames - startFrame)
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            guard let sample = silentSampleBuffer(
                sampleRate: sampleRate,
                channels: channels,
                frames: count,
                startFrame: startFrame
            ) else {
                fail("failed to build silent sample buffer")
            }
            if !input.append(sample) {
                fail("failed to append audio: \(writer.error?.localizedDescription ?? "unknown")")
            }
            startFrame += count
        }

        input.markAsFinished()
        await finish(writer)
    }

    // Zero-filled 16-bit signed PCM sample buffer.
    static func silentSampleBuffer(
        sampleRate: Double,
        channels: Int,
        frames: Int,
        startFrame: Int
    ) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(2 * channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(2 * channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        ) == noErr, let formatDesc = format else {
            return nil
        }

        let dataSize = frames * 2 * channels
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        ) == noErr, let block = blockBuffer else {
            return nil
        }
        CMBlockBufferFillDataBytes(
            with: 0,
            blockBuffer: block,
            offsetIntoDestination: 0,
            dataLength: dataSize
        )

        var sampleBuffer: CMSampleBuffer?
        let pts = CMTime(value: Int64(startFrame), timescale: Int32(sampleRate))
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: formatDesc,
            sampleCount: frames,
            presentationTimeStamp: pts,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr else {
            return nil
        }
        return sampleBuffer
    }

    static func finish(_ writer: AVAssetWriter) async {
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        if writer.status != .completed {
            fail("writer did not complete: \(writer.error?.localizedDescription ?? "unknown")")
        }
    }
}
