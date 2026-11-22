import AVFoundation
import CoreVideo
import Foundation
import Testing
@testable import YEN

/// Runs the real downloader against a stand-in for yt-dlp that copies local
/// media, so the stream handling is tested without the network.
@MainActor
struct YouTubeDownloaderTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private var cache: URL { folder.appendingPathComponent("cache") }
    private var calls: URL { folder.appendingPathComponent("calls.log") }
    private let link = "https://www.youtube.com/watch?v=aqz-KE-bpKQ"

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A 64 by 48 H.264 movie with no sound.
    private func makeVideo(named name: String) async throws -> URL {
        let url = folder.appendingPathComponent(name)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48,
        ])
        writer.add(input)
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<6 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer)
            try #require(adaptor.append(try #require(buffer), withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed)
        return url
    }

    /// A short AAC sound file.
    private func makeAudio(named name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_820))
        buffer.frameLength = 8_820
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
        ])
        try file.write(from: buffer)
        return url
    }

    /// A script in yt-dlp's place. Asked for separate streams, it writes the
    /// ones it is given under the names yt-dlp would use; asked for one file,
    /// it writes `single`. Each call is logged with its format request.
    private func makeDownloader(video: URL?, audio: URL?, single: URL?) throws -> YouTubeDownloader {
        func copy(_ source: URL?, to destination: String) -> String {
            source.map { "cp '\($0.path)' \"\(destination)\"" } ?? ":"
        }
        let script = folder.appendingPathComponent("yt-dlp-\(UUID().uuidString)")
        try """
        #!/bin/bash
        while [ $# -gt 0 ]; do
          case "$1" in
            -f) format="$2"; shift ;;
            -o) output="$2"; shift ;;
          esac
          shift
        done
        echo "$format" >> '\(calls.path)'
        echo "[download] Destination: stream"
        echo "[download] 100.0% of 1.00KiB"
        case "$format" in
          *,*)
            stem="${output%'%(format_id)s.%(ext)s'}"
            \(copy(audio, to: "${stem}140.m4a"))
            \(copy(video, to: "${stem}299.mp4"))
            ;;
          *)
            \(copy(single, to: "$output"))
            ;;
        esac
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let path = script.path
        return YouTubeDownloader(cacheDirectory: cache, resolveBinary: { path })
    }

    private func tracks(of url: URL) async throws -> [AVMediaType] {
        try await AVURLAsset(url: url).load(.tracks).map(\.mediaType)
    }

    private func cachedFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: cache.path).sorted()
    }

    @Test func separateStreamsBecomeOneMovieWithSound() async throws {
        defer { cleanUp() }
        let downloader = try makeDownloader(
            video: try await makeVideo(named: "video.mp4"), audio: try makeAudio(named: "audio.m4a"), single: nil
        )

        guard case .success(let movie) = await downloader.download(youtubeURL: link) else {
            Issue.record("the download did not succeed")
            return
        }

        #expect(try await tracks(of: movie) == [.video, .audio])
        let size = try await #require(AVURLAsset(url: movie).loadTracks(withMediaType: .video).first).load(.naturalSize)
        #expect(size == CGSize(width: 64, height: 48))
        // Only the finished movie stays in the cache.
        #expect(try cachedFiles() == [movie.lastPathComponent])
    }

    @Test func aVideoWithoutASeparateSoundStreamStillPlays() async throws {
        defer { cleanUp() }
        let downloader = try makeDownloader(video: try await makeVideo(named: "video.mp4"), audio: nil, single: nil)

        guard case .success(let movie) = await downloader.download(youtubeURL: link) else {
            Issue.record("the download did not succeed")
            return
        }

        #expect(try await tracks(of: movie) == [.video])
        #expect(try cachedFiles() == [movie.lastPathComponent])
    }

    @Test func aLinkWithNoSeparateVideoFallsBackToOneFile() async throws {
        defer { cleanUp() }
        let downloader = try makeDownloader(
            video: nil, audio: try makeAudio(named: "audio.m4a"), single: try await makeVideo(named: "single.mp4")
        )

        guard case .success(let movie) = await downloader.download(youtubeURL: link) else {
            Issue.record("the download did not succeed")
            return
        }

        #expect(try await tracks(of: movie) == [.video])
        #expect(try cachedFiles() == [movie.lastPathComponent])
        let requests = try String(contentsOf: calls, encoding: .utf8).split(separator: "\n")
        #expect(requests.count == 2)
    }

    @Test func aCachedMovieIsNotDownloadedAgain() async throws {
        defer { cleanUp() }
        let downloader = try makeDownloader(
            video: try await makeVideo(named: "video.mp4"), audio: try makeAudio(named: "audio.m4a"), single: nil
        )

        let first = await downloader.download(youtubeURL: link)
        let second = await downloader.download(youtubeURL: link)

        #expect(first == second)
        let requests = try String(contentsOf: calls, encoding: .utf8).split(separator: "\n")
        #expect(requests.count == 1)
    }

    /// The bar must only move forward across the two streams: the sound fills
    /// its first 5% and the video the rest.
    @Test func theProgressBarCoversBothStreamsInOrder() {
        let soundEnd = YouTubeDownloader.overallProgress(1, sound: true, twoStreams: true)
        let videoStart = YouTubeDownloader.overallProgress(0, sound: false, twoStreams: true)
        #expect(YouTubeDownloader.overallProgress(0, sound: true, twoStreams: true) == 0)
        #expect(soundEnd == videoStart)
        #expect(YouTubeDownloader.overallProgress(1, sound: false, twoStreams: true) == 1)
        #expect(YouTubeDownloader.overallProgress(0.4, sound: false, twoStreams: false) == 0.4)

        let log = "[download] Destination: /cache/aqz-KE-bpKQ.stream.140.m4a\n[download]  12.0% of 9.80MiB"
        #expect(YouTubeDownloader.startsSoundStream(in: log) == true)
        #expect(YouTubeDownloader.startsSoundStream(in: "[download] Destination: /cache/aqz-KE-bpKQ.stream.299.mp4\n") == false)
        #expect(YouTubeDownloader.startsSoundStream(in: "[download]  50.0% of 9.80MiB") == nil)
    }
}
