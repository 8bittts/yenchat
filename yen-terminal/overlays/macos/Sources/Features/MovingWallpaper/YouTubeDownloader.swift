import Foundation
import os

/// Downloads YouTube videos into the local cache with the pinned yt-dlp binary.
@MainActor
final class YouTubeDownloader {

    /// Result of a single `download` call.
    enum DownloadOutcome: Equatable {
        case success(URL)
        case failure(String)
        /// Cancelled before it finished — nothing to apply or report.
        case cancelled
    }

    /// Receives the fraction complete while this call's download runs, then
    /// `nil` once it ends. Never called for a cache hit.
    typealias ProgressHandler = @MainActor (Double?) -> Void

    /// Fraction complete of the download in flight, or nil when none is running.
    private(set) var progress: Double? {
        didSet {
            guard progress != oldValue else { return }
            progressHandler?(progress)
        }
    }

    private var progressHandler: ProgressHandler?
    private var process: Process?
    /// Identifies the subprocess run in flight. `cancel` clears it, so a run
    /// that exits without matching it was canceled.
    private var activeDownloadID: UUID?
    /// Whether the run in flight fetches the sound and the video as two streams.
    private var fetchesTwoStreams = false
    /// Whether the stream downloading now is the sound.
    private var downloadingSound = false

    /// Serializes downloads so concurrent per-display requests each run to
    /// completion instead of terminating one another's subprocess.
    private let gate = AsyncSerialGate()
    private let cacheDirectory: URL
    private let resolveBinary: @Sendable () async -> String?

    init(
        cacheDirectory: URL = MovingWallpaperPaths.youtubeCache,
        resolveBinary: @escaping @Sendable () async -> String? = { await YTDLPInstaller.ensureYTDLP() }
    ) {
        self.cacheDirectory = cacheDirectory
        self.resolveBinary = resolveBinary
    }

    // MARK: - Download

    /// Download a YouTube video into the cache, or return the cached file.
    /// Serialized: only one download runs at a time (FIFO), so concurrent
    /// per-display requests all complete instead of clobbering each other.
    func download(
        youtubeURL: String,
        onProgress: @escaping ProgressHandler = { _ in }
    ) async -> DownloadOutcome {
        await gate.run {
            await self.performDownload(youtubeURL: youtubeURL, onProgress: onProgress)
        } ?? .cancelled
    }

    /// Cancel the download in flight, if any. Queued downloads still run.
    func cancel() {
        if let activeDownloadID {
            cancel(activeDownloadID)
        }
    }

    /// Scoped to one run, so a cancellation that lands late cannot terminate
    /// the download that started after it.
    private func cancel(_ downloadID: UUID) {
        guard downloadID == activeDownloadID else { return }
        activeDownloadID = nil
        progress = nil
        process?.terminate()
    }

    private func performDownload(
        youtubeURL: String,
        onProgress: @escaping ProgressHandler
    ) async -> DownloadOutcome {
        guard let videoID = YouTubeURLParser.videoID(from: youtubeURL) else {
            return .failure("That doesn't look like a YouTube URL.")
        }

        // Named apart from the single 360p files earlier builds cached as `<id>.mp4`.
        let output = cacheDirectory.appending(path: "\(videoID).1080p.mp4")
        if FileManager.default.fileExists(atPath: output.path(percentEncoded: false)) {
            return .success(output)
        }

        guard let ytdlp = await resolveBinary() else {
            return .failure("YEN couldn't install its YouTube downloader. Check your internet connection.")
        }
        guard !Task.isCancelled else { return .cancelled }

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        excludeCacheFromBackup()
        // A quit or crash mid-run leaves stream files behind; they must not be
        // taken for this run's.
        removeIntermediates(videoID: videoID)

        let downloadID = UUID()
        activeDownloadID = downloadID
        progressHandler = onProgress
        progress = 0

        let outcome = await fetch(videoID: videoID, youtubeURL: youtubeURL, binary: ytdlp, downloadID: downloadID, into: output)

        activeDownloadID = nil
        progress = nil
        progressHandler = nil
        removeIntermediates(videoID: videoID)
        return outcome
    }

    /// YouTube serves one file with picture and sound only at 360p. Fetch the
    /// best H.264 video up to 1080p and its sound as two streams and merge them
    /// here. A link with no such video stream falls back to the single file.
    private func fetch(
        videoID: String,
        youtubeURL: String,
        binary: String,
        downloadID: UUID,
        into output: URL
    ) async -> DownloadOutcome {
        let streamStem = cacheDirectory.appending(path: Self.streamPrefix(videoID)).path(percentEncoded: false)
        fetchesTwoStreams = true
        let streams = await runYTDLP(
            binary: binary,
            downloadID: downloadID,
            arguments: Self.arguments(
                // The sound comes first: it is small, so the bar moves at once.
                format: "bestaudio[ext=m4a],bestvideo[ext=mp4][vcodec^=avc1][height<=1080]",
                output: streamStem + "%(format_id)s.%(ext)s",
                youtubeURL: youtubeURL
            )
        )
        fetchesTwoStreams = false
        switch streams {
        case .failed(let message): return .failure(message)
        case .cancelled: return .cancelled
        case .succeeded: break
        }

        // yt-dlp fetches whichever of the two streams exists and reports success.
        let files = streamFiles(videoID: videoID)
        if let video = files.first(where: { $0.pathExtension == "mp4" }) {
            let merged = URL(filePath: streamStem + "merged.mp4")
            let done = await YouTubeStreamMerger.merge(
                video: video,
                audio: files.first { $0.pathExtension == "m4a" },
                into: merged
            )
            guard activeDownloadID == downloadID, !Task.isCancelled else { return .cancelled }
            guard done, (try? FileManager.default.moveItem(at: merged, to: output)) != nil else {
                return .failure("The download finished, but the video couldn't be prepared.")
            }
            return .success(output)
        }

        progress = 0
        let single = await runYTDLP(
            binary: binary,
            downloadID: downloadID,
            arguments: Self.arguments(
                format: "best[ext=mp4][height<=1080]/best[ext=mp4]",
                output: output.path(percentEncoded: false),
                youtubeURL: youtubeURL
            )
        )
        switch single {
        case .failed(let message): return .failure(message)
        case .cancelled: return .cancelled
        case .succeeded:
            guard FileManager.default.fileExists(atPath: output.path(percentEncoded: false)) else {
                return .failure("The download finished, but the video file is missing.")
            }
            return .success(output)
        }
    }

    private nonisolated static func arguments(format: String, output: String, youtubeURL: String) -> [String] {
        [
            "-f", format,
            "--ignore-config", "--no-plugin-dirs", "--no-playlist",
            // Leave each file as downloaded, whether or not ffmpeg is installed.
            "--fixup", "never",
            "--newline",
            "--progress",
            // Bound network stalls so a hung connection self-terminates instead
            // of wedging the serial download gate indefinitely.
            "--socket-timeout", "30",
            "--retries", "3",
            "-o", output,
            youtubeURL,
        ]
    }

    private nonisolated static func streamPrefix(_ videoID: String) -> String {
        "\(videoID).stream."
    }

    private func streamFiles(videoID: String) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return entries.filter { $0.lastPathComponent.hasPrefix(Self.streamPrefix(videoID)) }
    }

    /// The sound stream gets the first 5% of the bar and the video the rest; a
    /// single file uses the whole bar.
    nonisolated static func overallProgress(_ fraction: Double, sound: Bool, twoStreams: Bool) -> Double {
        guard twoStreams else { return fraction }
        return sound ? fraction * 0.05 : 0.05 + fraction * 0.95
    }

    /// Apple: exclude files the app can download again, such as videos kept for
    /// offline viewing, from backups. Every file here can be fetched again from
    /// its saved YouTube URL; the Photos caches cannot, so they stay backed up.
    private func excludeCacheFromBackup() {
        var directory = cacheDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try directory.setResourceValues(values)
        } catch {
            WallpaperLog.youtube.error("Couldn't exclude the YouTube cache from backup: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Remove what a run leaves beside its finished movie: the two stream
    /// files, the merge in progress, and yt-dlp's `.part` and `.ytdl` files.
    /// A movie cached earlier for the same video is never touched.
    private func removeIntermediates(videoID: String) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        let prefixes = [Self.streamPrefix(videoID), "\(videoID).1080p.mp4."]
        for entry in entries where prefixes.contains(where: entry.lastPathComponent.hasPrefix) {
            try? fileManager.removeItem(at: entry)
        }
    }

    // MARK: - Process Runner

    private enum RunResult {
        case succeeded
        case failed(String)
        case cancelled
    }

    /// What one subprocess run left behind, gathered off the main actor.
    private struct ProcessExit {
        var status: Int32 = 0
        var errorOutput = Data()
        /// Set when the process never launched.
        var launchError: String?
    }

    /// The inherited environment with the Homebrew locations on `PATH`, where
    /// yt-dlp looks for a JavaScript runtime.
    private static var processEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let inherited = (environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init)
        var seen = Set<String>()
        environment["PATH"] = (["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] + inherited)
            .filter { seen.insert($0).inserted }
            .joined(separator: ":")
        return environment
    }

    /// Compiled once, not per stdout chunk. Matches yt-dlp progress like "45.2%".
    private nonisolated static let progressRegex = try! NSRegularExpression(pattern: #"(\d+\.\d+)%"#)

    /// The fraction in a yt-dlp progress line like "[download]  45.2% of ~12.34MiB".
    nonisolated static func progressFraction(in output: String) -> Double? {
        let range = NSRange(output.startIndex..., in: output)
        guard let match = progressRegex.firstMatch(in: output, range: range),
              let percentRange = Range(match.range(at: 1), in: output),
              let percent = Double(output[percentRange])
        else { return nil }
        return percent / 100
    }

    /// Whether the last file yt-dlp started in this output is the sound stream,
    /// or nil when it started none.
    nonisolated static func startsSoundStream(in output: String) -> Bool? {
        guard let marker = output.range(of: "[download] Destination:", options: .backwards) else { return nil }
        let line = output[marker.upperBound...].prefix { !$0.isNewline }
        return line.trimmingCharacters(in: .whitespaces).hasSuffix(".m4a")
    }

    /// The text after yt-dlp's last "ERROR:" marker, or a generic message.
    nonisolated static func failureMessage(fromStandardError data: Data) -> String {
        let text = String(decoding: data, as: UTF8.self)
        let fallback = "The download failed."
        guard let marker = text.range(of: "ERROR:", options: .backwards) else { return fallback }
        let message = text[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? fallback : message
    }

    private func runYTDLP(binary: String, downloadID: UUID, arguments: [String]) async -> RunResult {
        await withTaskCancellationHandler {
            await runYTDLPSubprocess(binary: binary, downloadID: downloadID, arguments: arguments)
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(downloadID) }
        }
    }

    private func runYTDLPSubprocess(binary: String, downloadID: UUID, arguments: [String]) async -> RunResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(filePath: binary)
            process.arguments = arguments
            process.environment = Self.processEnvironment

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // A run is over when the process has exited AND stderr has reached its
            // end. Waiting for both, without blocking a thread on either, means the
            // closing "ERROR:" line cannot be lost to a read still in flight when
            // the process exits.
            let finished = DispatchGroup()
            let exit = OSAllocatedUnfairLock(initialState: ProcessExit())
            finished.enter() // the process exits
            finished.enter() // stderr ends

            process.terminationHandler = { process in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                exit.withLock { $0.status = process.terminationStatus }
                finished.leave()
            }

            finished.notify(queue: .main) { [weak self] in
                // Holding the pipe here keeps its read handler alive until the end.
                _ = errorPipe
                let exit = exit.withLock { $0 }
                MainActor.assumeIsolated {
                    guard let self else {
                        continuation.resume(returning: .cancelled)
                        return
                    }
                    self.process = nil
                    if let launchError = exit.launchError {
                        continuation.resume(returning: .failed("The YouTube downloader couldn't start. \(launchError)"))
                    } else if self.activeDownloadID != downloadID {
                        continuation.resume(returning: .cancelled)
                    } else if exit.status == 0 {
                        continuation.resume(returning: .succeeded)
                    } else {
                        continuation.resume(returning: .failed(Self.failureMessage(fromStandardError: exit.errorOutput)))
                    }
                }
            }

            do {
                try process.run()
                self.process = process
            } catch {
                // Nothing launched, so neither event will arrive. No read handler is
                // installed yet, so both are settled here, exactly once.
                process.terminationHandler = nil
                exit.withLock { $0.launchError = error.localizedDescription }
                finished.leave()
                finished.leave()
                return
            }

            // Installed after launch: output written before this point waits in the
            // pipe. Draining stderr as it arrives also keeps a chatty run from
            // filling the pipe and blocking the child. An empty read is its end.
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    finished.leave()
                } else {
                    exit.withLock { $0.errorOutput.append(chunk) }
                }
            }

            // The termination handler also clears this one, but it can run before
            // this line installs it; an empty read is the end, so clear it there too.
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                let text = String(decoding: chunk, as: UTF8.self)
                let startsSound = Self.startsSoundStream(in: text)
                let fraction = Self.progressFraction(in: text)
                guard startsSound != nil || fraction != nil else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.activeDownloadID == downloadID else { return }
                    if let startsSound { self.downloadingSound = startsSound }
                    if let fraction {
                        self.progress = Self.overallProgress(
                            fraction, sound: self.downloadingSound, twoStreams: self.fetchesTwoStreams
                        )
                    }
                }
            }
        }
    }
}
