import AppKit
import Foundation
import Testing
@testable import YEN

/// The Settings wallpaper buttons: Demo, Remove, and the state the row shows.
@MainActor
@Suite(.serialized)
struct WallpaperControlsTests {
    private let defaults = WallpaperMemoryDefaults()
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let wallpaper: URL
    private let otherWallpaper: URL

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // One-pixel GIFs: real files the engine accepts, with no video decode.
        let gif = try #require(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))
        wallpaper = folder.appendingPathComponent("loop.gif")
        otherWallpaper = folder.appendingPathComponent("other.gif")
        try gif.write(to: wallpaper)
        try gif.write(to: otherWallpaper)
    }

    private var store: WallpaperPersistenceStore { WallpaperPersistenceStore(userDefaults: defaults) }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }

    private static func snapshot(displayID: CGDirectDisplayID, spaces: [UInt64], current: UInt64) -> ManagedDisplaySpacesSnapshot {
        let identifier = "TEST-DISPLAY-UUID"
        return ManagedDisplaySpacesSnapshot.from(
            rawEntries: [[
                "Display Identifier": identifier,
                "Current Space": ["id64": NSNumber(value: current)],
                "Spaces": spaces.map { ["id64": NSNumber(value: $0)] },
            ]],
            screensByDisplayIdentifier: [identifier: displayID],
            fallbackGlobalSpaceID: 1
        )
    }

    // MARK: - Demo

    @Test func demoAlwaysPicksAnotherClipAndReachesEveryOther() {
        var generator = SystemRandomNumberGenerator()
        for current in DemoWallpapers.fileNames {
            var seen = Set<String>()
            for _ in 0..<500 {
                seen.insert(DemoWallpapers.next(after: current, using: &generator))
            }
            #expect(!seen.contains(current), "\(current) repeated itself")
            #expect(seen == Set(DemoWallpapers.fileNames).subtracting([current]))
        }
    }

    @Test func demoClipsAreFilesTheEnginePlays() {
        for name in DemoWallpapers.fileNames {
            #expect(WallpaperFileType.detect(for: URL(filePath: "/tmp/\(name)")) != nil, "\(name)")
        }
    }

    @Test func aDownloadedClipLandsInTheCache() async throws {
        defer { cleanUp() }
        let cache = folder.appendingPathComponent("Demo")
        let body = Data("clip".utf8)
        let session = DemoStubProtocol.session(status: 200, body: body)

        let outcome = await DemoWallpapers.download("test-01.mp4", into: cache, session: session)

        let file = cache.appendingPathComponent("test-01.mp4")
        #expect(outcome == .video(file))
        #expect(try Data(contentsOf: file) == body)
        #expect(DemoWallpapers.cachedURL("test-01.mp4", in: cache) == file)
        #expect(DemoStubProtocol.lastURL == URL(string: "https://yen.chat/videos/test-01.mp4"))
    }

    @Test func aFailedDownloadLeavesNothingBehind() async {
        defer { cleanUp() }
        let cache = folder.appendingPathComponent("Demo")
        let session = DemoStubProtocol.session(status: 404, body: Data("Not Found".utf8))

        let outcome = await DemoWallpapers.download("test-02.mp4", into: cache, session: session)

        guard case .failed = outcome else {
            Issue.record("a 404 must fail, got \(outcome)")
            return
        }
        #expect(DemoWallpapers.cachedURL("test-02.mp4", in: cache) == nil)
    }

    @Test func aCancelledRequestCannotOpenItsLoadingOverlay() async {
        defer { cleanUp() }
        let requests = WallpaperRequestCoordinator()
        var started = false
        let task = requests.start(for: .allDesktops) { _ in started = true }
        requests.cancelAll()
        await task.value
        #expect(!started)
    }

    // MARK: - Remove and state

    @Test func removeInPerDesktopModeClearsOnlyTheCurrentDesktop() throws {
        defer { cleanUp() }
        let displayID = try #require(NSScreen.screens.first?.displayID)
        var saved = WallpaperState()
        saved.entries[DesktopKey(displayID: displayID, spaceID: 1501)] = WallpaperEntry(localURL: wallpaper)
        saved.entries[DesktopKey(displayID: displayID, spaceID: 1502)] = WallpaperEntry(localURL: otherWallpaper)
        store.save(mode: .perDesktop, isMuted: true, state: saved)
        let live = Self.snapshot(displayID: displayID, spaces: [1501, 1502], current: 1502)
        let manager = WallpaperManager(persistenceStore: store, spacesSnapshot: { live })
        defer { manager.tearDown() }

        let before = manager.controlsInput().state
        #expect(before.perDesktop)
        #expect(before.fileName == "other.gif")

        manager.clearCurrentWallpaper()

        #expect(store.load().state.entries.mapValues(\.localURL.lastPathComponent)
            == [DesktopKey(displayID: displayID, spaceID: 1501): "loop.gif"])
        let after = manager.controlsInput().state
        #expect(after.fileName == nil)
        #expect(after.hasAnyWallpaper)
    }

    @Test func removeInAllDesktopsModeClearsEverythingAndReportsIt() throws {
        defer { cleanUp() }
        try #require(!NSScreen.screens.isEmpty)
        let manager = WallpaperManager(persistenceStore: store)
        defer { manager.tearDown() }
        manager.setWallpaper(url: wallpaper)
        #expect(manager.controlsInput().state.fileName == "loop.gif")

        var changes = 0
        manager.onChange = { changes += 1 }
        manager.clearCurrentWallpaper()

        let state = manager.controlsInput().state
        #expect(state.fileName == nil)
        #expect(!state.hasAnyWallpaper)
        #expect(changes > 0, "the Settings row must hear about the removal")
    }

    @Test func playbackButtonsReportTheirState() throws {
        defer { cleanUp() }
        try #require(!NSScreen.screens.isEmpty)
        let manager = WallpaperManager(persistenceStore: store)
        defer { manager.tearDown() }
        manager.setWallpaper(url: wallpaper)
        var changes = 0
        manager.onChange = { changes += 1 }

        manager.togglePause()
        #expect(manager.controlsInput().state.isPaused)
        manager.toggleMute()
        #expect(!manager.controlsInput().state.isMuted)
        manager.togglePerDesktop()
        #expect(manager.controlsInput().state.perDesktop)
        #expect(changes >= 3)
    }
}

/// Answers every request with one fixed response, and records the URL asked for.
final class DemoStubProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var lastURL: URL?

    static func session(status: Int, body: Data) -> URLSession {
        self.status = status
        self.body = body
        lastURL = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DemoStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lastURL = url
        let response = HTTPURLResponse(url: url, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
