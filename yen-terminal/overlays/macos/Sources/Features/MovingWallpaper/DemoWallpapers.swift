import Foundation

/// Sample clips the website serves from `public/videos`, so a user can try
/// Moving Wallpaper without media of their own. A clip downloads once, on the
/// first Demo press that picks it, and stays in `MovingWallpaperPaths.demoCache`.
/// `tests/186-demo-wallpapers.test.ts` keeps `fileNames` equal to that folder.
enum DemoWallpapers {
    static let baseURL = URL(string: "https://yen.chat/videos/")!

    static let fileNames = [
        "test-00.gif",
        "test-01.mp4",
        "test-02.mp4",
        "test-03.mp4",
        "test-04.mp4",
        "test-05.mp4",
        "test-06.mp4",
        "test-07.mp4",
        "test-08.mp4",
        "test-09.mp4",
    ]

    enum Outcome: Equatable {
        case video(URL)
        case failed(String)
    }

    /// A random clip other than `current`, so every press changes the wallpaper.
    static func next<G: RandomNumberGenerator>(after current: String?, using generator: inout G) -> String {
        let choices = fileNames.filter { $0 != current }
        return choices.randomElement(using: &generator) ?? fileNames[0]
    }

    /// The clip's file when an earlier press already downloaded it.
    static func cachedURL(_ name: String, in cache: URL = MovingWallpaperPaths.demoCache) -> URL? {
        let url = cache.appending(path: name, directoryHint: .notDirectory)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// Download one clip into the cache. The file appears only when the whole
    /// download succeeded, so a cancelled or failed one leaves nothing behind.
    static func download(
        _ name: String,
        from base: URL = baseURL,
        into cache: URL = MovingWallpaperPaths.demoCache,
        session: URLSession = .shared
    ) async -> Outcome {
        let destination = cache.appending(path: name, directoryHint: .notDirectory)
        do {
            let (temporary, response) = try await session.download(from: base.appending(path: name))
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return .failed("yen.chat did not return the demo video. Try again later.")
            }
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            return .video(destination)
        } catch {
            return .failed("The demo video could not be downloaded. Check your connection and try again.")
        }
    }
}
