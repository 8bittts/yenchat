import AVFoundation

/// Copies a downloaded video stream, and its sound stream when there is one,
/// into a single MP4 without re-encoding, so no ffmpeg is needed.
///
/// YouTube serves its high-resolution video and its sound as separate
/// fragmented files. AVFoundation reads each at twice its real length, and the
/// reader ends each with an empty marker buffer at that doubled time. Copying
/// only the buffers that carry samples gives the movie its real length.
enum YouTubeStreamMerger {
    static func merge(video: URL, audio: URL?, into output: URL) async -> Bool {
        try? FileManager.default.removeItem(at: output)
        guard let writer = try? AVAssetWriter(outputURL: output, fileType: .mp4) else { return false }
        do {
            var readers: [AVAssetReader] = []
            var copies: [Copy] = []
            for (url, type) in [(video, AVMediaType.video), (audio, AVMediaType.audio)] {
                guard let url else { continue }
                let asset = AVURLAsset(url: url)
                guard let track = try await asset.loadTracks(withMediaType: type).first else { return false }
                let reader = try AVAssetReader(asset: asset)
                let input = AVAssetWriterInput(
                    mediaType: type,
                    outputSettings: nil,
                    sourceFormatHint: try await track.load(.formatDescriptions).first
                )
                copies.append(Copy(
                    provider: reader.outputProvider(for: AVAssetReaderTrackOutput(track: track, outputSettings: nil)),
                    receiver: writer.inputReceiver(for: input)
                ))
                readers.append(reader)
            }
            try writer.start()
            writer.startSession(atSourceTime: .zero)
            for reader in readers { try reader.start() }
            // The writer interleaves the tracks, so each must be fed while the
            // other waits.
            try await withThrowingTaskGroup(of: Void.self) { group in
                for copy in copies {
                    group.addTask { try await copy.run() }
                }
                try await group.waitForAll()
            }
            await writer.finishWriting()
            return writer.status == .completed && readers.allSatisfy { $0.status == .completed }
        } catch {
            writer.cancelWriting()
            return false
        }
    }

    /// One track's reader output and writer input. Each is used by one task only.
    private struct Copy: @unchecked Sendable {
        let provider: AVAssetReaderOutput.Provider<CMReadySampleBuffer<CMSampleBuffer.DynamicContent>>
        let receiver: AVAssetWriterInput.SampleBufferReceiver

        func run() async throws {
            while let buffer = try await provider.next() {
                // A marker buffer carries no samples; the last one sits at the
                // doubled track end and would stretch the movie to it.
                if buffer.withUnsafeSampleBuffer({ $0.numSamples }) == 0 { continue }
                try await receiver.append(buffer)
            }
            receiver.finish()
        }
    }
}
