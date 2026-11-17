import AppKit
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct TerminalBackgroundImageLoaderTests {
    private let url = URL(fileURLWithPath: "/tmp/yen-background-loader-test.png")
    private let cacheKey = "shared-background-key"

    @Test func simultaneousWindowsShareOneDecodeAndOneCachedImage() async throws {
        let probe = ControlledBackgroundDecodeProbe()
        let loader = makeLoader(decoder: { _ in await probe.decode() })

        let firstRequest = Task { @MainActor in await imageIdentity(loader) }
        await probe.waitUntilStarted()
        let secondRequest = Task { @MainActor in await imageIdentity(loader) }

        let joinedSharedLoad = await waitUntil {
            loader._testInFlightWaiterCount(forCacheKey: cacheKey) == 2
        }
        #expect(joinedSharedLoad)

        await probe.release()
        let firstResult = await firstRequest.value
        let secondResult = await secondRequest.value
        let firstImageID = try #require(firstResult)
        let secondImageID = try #require(secondResult)

        #expect(firstImageID == secondImageID)
        #expect(await probe.currentDecodeCount() == 1)

        let cachedImage = try #require(await loader.image(at: url))
        #expect(ObjectIdentifier(cachedImage) == firstImageID)
        #expect(await probe.currentDecodeCount() == 1)
    }

    @Test func cancellingOneSharedWaiterKeepsDecodeAliveForRemainingWindow() async throws {
        let probe = ControlledBackgroundDecodeProbe()
        let loader = makeLoader(decoder: { _ in await probe.decode() })

        let cancelledRequest = Task { @MainActor in await imageIdentity(loader) }
        await probe.waitUntilStarted()
        let activeRequest = Task { @MainActor in await imageIdentity(loader) }
        let joinedSharedLoad = await waitUntil {
            loader._testInFlightWaiterCount(forCacheKey: cacheKey) == 2
        }
        #expect(joinedSharedLoad)

        cancelledRequest.cancel()
        let releasedCancelledWaiter = await waitUntil {
            loader._testInFlightWaiterCount(forCacheKey: cacheKey) == 1
        }
        #expect(releasedCancelledWaiter)
        #expect(await probe.currentCancellationCount() == 0)

        await probe.release()
        let cancelledResult = await cancelledRequest.value
        let activeResult = await activeRequest.value

        #expect(cancelledResult == nil)
        #expect(activeResult != nil)
        #expect(await probe.currentDecodeCount() == 1)
        #expect(await probe.currentCancellationCount() == 0)
    }

    @Test func cancellingLastWaiterCancelsWorkerAndDoesNotCacheItsStaleResult() async throws {
        let probe = CancellationIgnoringBackgroundDecodeProbe()
        let loader = makeLoader(decoder: { _ in await probe.decode() })

        let cancelledRequest = Task { @MainActor in await imageIdentity(loader) }
        await probe.waitUntilStarted()
        cancelledRequest.cancel()
        let cancelledResult = await cancelledRequest.value

        #expect(cancelledResult == nil)
        #expect(await probe.observedCancellation())
        #expect(loader._testInFlightWaiterCount(forCacheKey: cacheKey) == 0)

        let freshResult = await loader.image(at: url)
        #expect(freshResult != nil)
        #expect(await probe.currentDecodeCount() == 2)
    }

    @Test func cacheIsBoundedSoStaleWallpaperDecodesEvictInsteadOfAccumulating() {
        let loader = makeLoader(decoder: { _ in makeBackgroundLoaderTestImage() })
        // Each distinct (path, mtime) key is a full-resolution decode (~33 MB at 4K);
        // without a bound they accumulated until memory pressure. The loader must cap
        // both entry count and total decoded-byte cost.
        #expect(loader._testCacheCountLimit == 8)
        #expect(loader._testCacheTotalCostLimit == 256 * 1024 * 1024)
    }

    /// Task results must be `Sendable`, and `NSImage` is only `Sendable` from macOS 14,
    /// so requests made inside a `Task` return the image's identity instead. The loader's
    /// cache keeps the image alive, so equal identities mean the same instance.
    private func imageIdentity(_ loader: TerminalBackgroundImageLoader) async -> ObjectIdentifier? {
        await loader.image(at: url).map(ObjectIdentifier.init)
    }

    private func makeLoader(
        decoder: @escaping TerminalBackgroundImageLoader.Decoder
    ) -> TerminalBackgroundImageLoader {
        TerminalBackgroundImageLoader(
            cacheKeyResolver: { [cacheKey] _ in cacheKey },
            decoder: decoder
        )
    }

    private func waitUntil(
        attempts: Int = 200,
        condition: @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<attempts {
            if condition() {
                return true
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return condition()
    }
}

private actor ControlledBackgroundDecodeProbe {
    private var decodeCount = 0
    private var cancellationCount = 0
    private var isReleased = false
    private var cancellationWasObserved = false
    private var releaseContinuations: [CheckedContinuation<Bool, Never>] = []
    private var startContinuations: [CheckedContinuation<Void, Never>] = []

    func decode() async -> CGImage? {
        decodeCount += 1
        let continuations = startContinuations
        startContinuations.removeAll()
        continuations.forEach { $0.resume() }

        let completedNormally = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if isReleased {
                    continuation.resume(returning: true)
                } else if cancellationWasObserved {
                    continuation.resume(returning: false)
                } else {
                    releaseContinuations.append(continuation)
                }
            }
        } onCancel: {
            Task { await self.cancelPendingDecode() }
        }

        guard completedNormally, !Task.isCancelled else { return nil }
        return makeBackgroundLoaderTestImage()
    }

    func waitUntilStarted() async {
        if decodeCount > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let continuations = releaseContinuations
        releaseContinuations.removeAll()
        continuations.forEach { $0.resume(returning: true) }
    }

    func currentDecodeCount() -> Int {
        decodeCount
    }

    func currentCancellationCount() -> Int {
        cancellationCount
    }

    private func cancelPendingDecode() {
        cancellationCount += 1
        cancellationWasObserved = true
        let continuations = releaseContinuations
        releaseContinuations.removeAll()
        continuations.forEach { $0.resume(returning: false) }
    }
}

private actor CancellationIgnoringBackgroundDecodeProbe {
    private var decodeCount = 0
    private var didObserveCancellation = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []

    func decode() async -> CGImage? {
        decodeCount += 1
        let currentDecode = decodeCount
        let continuations = startContinuations
        startContinuations.removeAll()
        continuations.forEach { $0.resume() }

        if currentDecode == 1 {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                didObserveCancellation = Task.isCancelled
            }
        }

        // Deliberately return an image even after cancellation. The loader must reject
        // this stale worker result instead of publishing or caching it.
        return makeBackgroundLoaderTestImage()
    }

    func waitUntilStarted() async {
        if decodeCount > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func observedCancellation() -> Bool {
        didObserveCancellation
    }

    func currentDecodeCount() -> Int {
        decodeCount
    }
}

private func makeBackgroundLoaderTestImage() -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    return context.makeImage()
}
