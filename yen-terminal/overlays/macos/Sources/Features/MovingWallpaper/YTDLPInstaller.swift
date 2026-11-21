import CryptoKit
import Foundation

/// Pins, verifies, and installs the yt-dlp binary used by `YouTubeDownloader`.
@available(macOS 27.0, *)
enum YTDLPInstaller {
    /// Pinned yt-dlp release. Bump both fields together — the SHA-256 is checked
    /// against the downloaded binary before it's installed and made executable.
    /// Refresh via `curl -fsSL https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest`
    /// when YouTube site changes break the current pinned version.
    static let pinnedVersion = "2026.10.26"
    static let pinnedSHA256 = "0f922c15ccc0b83eefa1c8bc9104e434318c4bf16e408e1ee93b7745a6efe0aa"

    private static func verified(_ url: URL) throws -> Bool {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while true {
            try Task.checkCancellation()
            let done = try autoreleasepool {
                guard let bytes = try file.read(upToCount: 65536), !bytes.isEmpty else { return true }
                hash.update(data: bytes)
                return false
            }
            if done { break }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined() == pinnedSHA256
    }

    static func ensureYTDLP() async -> String? {

        let installURL = MovingWallpaperPaths.ytdlpBinary
        let installedPath = installURL.path(percentEncoded: false)

        if FileManager.default.fileExists(atPath: installedPath) {
            if (try? verified(installURL)) == true {
                return installedPath
            }
            // Corrupt, tampered, or stale after a pin bump — discard and re-fetch.
            WallpaperLog.youtube.error("Installed yt-dlp failed SHA-256 verification; re-downloading")
            guard !Task.isCancelled else { return nil }
        }

        return await downloadAndInstallYTDLP()
    }

    private static func downloadAndInstallYTDLP() async -> String? {
        let installURL = MovingWallpaperPaths.ytdlpBinary
        let dir = installURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let downloadURL = URL(string:
            "https://github.com/yt-dlp/yt-dlp/releases/download/\(pinnedVersion)/yt-dlp_macos"
        )!
        do {
            let (temp, response) = try await URLSession.shared.download(from: downloadURL)
            defer { try? FileManager.default.removeItem(at: temp) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                WallpaperLog.youtube.error("yt-dlp \(pinnedVersion, privacy: .public) download returned HTTP \(status, privacy: .public)")
                return nil
            }
            guard try verified(temp) else {
                WallpaperLog.youtube.error("yt-dlp SHA-256 mismatch for pinned version \(pinnedVersion, privacy: .public); refusing to install")
                return nil
            }
            // Atomic write: a crash/disk-full mid-write can't leave a truncated,
            // permanently-poisoned binary that the existence-only path check trusts.
            let staged = dir.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: staged) }
            try FileManager.default.copyItem(at: temp, to: staged)
            try Task.checkCancellation()
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: staged.path
            )
            guard rename(staged.path, installURL.path) == 0 else { return nil }
            return installURL.path(percentEncoded: false)
        } catch {
            WallpaperLog.youtube.error("yt-dlp install failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
