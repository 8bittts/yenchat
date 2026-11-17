import AppKit
import ImageIO
import SwiftUI
import YENKit
import os

/// Process-wide loader and cache for terminal background images, keyed by file path +
/// modification date so overwriting the file (same path, new content) busts the entry.
///
/// Every terminal window renders the same background file through its own
/// `WholeWindowBackgroundView`. The loader coalesces simultaneous cache misses so an
/// N-window restore performs one decode and every window retains the same `NSImage`
/// instance (a 4K background is ~33 MB decoded — 5 windows stay near ~33 MB total).
@MainActor
final class TerminalBackgroundImageLoader {
    typealias CacheKeyResolver = @Sendable (URL) -> String?
    typealias Decoder = @Sendable (URL) async -> CGImage?

    static let shared = TerminalBackgroundImageLoader(
        cacheKeyResolver: { resolveCacheKey(for: $0) },
        decoder: { await decodeImage(at: $0) }
    )

    private struct InFlightLoad {
        let generation: UUID
        let task: Task<CGImage?, Never>
        var waiterIDs: Set<UUID>
    }

    private struct LoadLease {
        let cacheKey: String
        let generation: UUID
        let waiterID: UUID
        let task: Task<CGImage?, Never>
    }

    private let cache = NSCache<NSString, NSImage>()
    private let cacheKeyResolver: CacheKeyResolver
    private let decoder: Decoder
    private var inFlightLoads: [String: InFlightLoad] = [:]

    init(
        cacheKeyResolver: @escaping CacheKeyResolver,
        decoder: @escaping Decoder
    ) {
        self.cacheKeyResolver = cacheKeyResolver
        self.decoder = decoder
        // Bound the decoded-wallpaper cache: each distinct (path, mtime) key is a
        // full-resolution decode (a 4K background is ~33 MB), so swapping or editing
        // backgrounds over a long session accumulated many large NSImages that were
        // only reclaimed under (rare on macOS) memory pressure. Evict LRU instead.
        cache.countLimit = 8
        cache.totalCostLimit = 256 * 1024 * 1024
    }

    func image(at url: URL) async -> NSImage? {
        let resolver = cacheKeyResolver
        let keyTask: Task<String?, Never> = Task.detached(priority: .utility) {
            guard !Task.isCancelled else { return nil }
            return resolver(url)
        }
        let cacheKey = await withTaskCancellationHandler {
            await keyTask.value
        } onCancel: {
            keyTask.cancel()
        }
        guard !Task.isCancelled else { return nil }

        if let cacheKey,
           let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }

        guard let decoded = await decodedImage(at: url, cacheKey: cacheKey),
              !Task.isCancelled else {
            return nil
        }

        // A sibling waiter may have populated the cache while this caller resumed.
        if let cacheKey,
           let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }

        let loaded = NSImage(cgImage: decoded, size: .zero)
        if let cacheKey {
            // Cost = decoded byte size so totalCostLimit bounds by memory, not just count.
            let byteCost = decoded.width * decoded.height * 4
            cache.setObject(loaded, forKey: cacheKey as NSString, cost: byteCost)
        }
        return loaded
    }

    func _testInFlightWaiterCount(forCacheKey cacheKey: String) -> Int {
        inFlightLoads[cacheKey]?.waiterIDs.count ?? 0
    }

    var _testCacheCountLimit: Int { cache.countLimit }
    var _testCacheTotalCostLimit: Int { cache.totalCostLimit }

    private func decodedImage(at url: URL, cacheKey: String?) async -> CGImage? {
        guard let cacheKey else {
            let task = makeDecodeTask(for: url)
            let decoded = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
            guard !Task.isCancelled else { return nil }
            return decoded
        }

        let lease = beginLoad(at: url, cacheKey: cacheKey)
        let decoded = await withTaskCancellationHandler {
            await lease.task.value
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.removeWaiter(for: lease, cancelWorkerIfLast: true)
            }
        }
        removeWaiter(for: lease, cancelWorkerIfLast: false)
        guard !Task.isCancelled else { return nil }
        return decoded
    }

    private func beginLoad(at url: URL, cacheKey: String) -> LoadLease {
        let waiterID = UUID()
        if var existing = inFlightLoads[cacheKey] {
            existing.waiterIDs.insert(waiterID)
            inFlightLoads[cacheKey] = existing
            return LoadLease(
                cacheKey: cacheKey,
                generation: existing.generation,
                waiterID: waiterID,
                task: existing.task
            )
        }

        let generation = UUID()
        let task = makeDecodeTask(for: url)
        inFlightLoads[cacheKey] = InFlightLoad(
            generation: generation,
            task: task,
            waiterIDs: [waiterID]
        )
        return LoadLease(
            cacheKey: cacheKey,
            generation: generation,
            waiterID: waiterID,
            task: task
        )
    }

    private func removeWaiter(for lease: LoadLease, cancelWorkerIfLast: Bool) {
        guard var load = inFlightLoads[lease.cacheKey],
              load.generation == lease.generation,
              load.waiterIDs.remove(lease.waiterID) != nil else {
            return
        }

        guard load.waiterIDs.isEmpty else {
            inFlightLoads[lease.cacheKey] = load
            return
        }

        inFlightLoads.removeValue(forKey: lease.cacheKey)
        if cancelWorkerIfLast {
            load.task.cancel()
        }
    }

    private func makeDecodeTask(for url: URL) -> Task<CGImage?, Never> {
        let decoder = decoder
        return Task.detached(priority: .utility) {
            guard !Task.isCancelled else { return nil }
            return await decoder(url)
        }
    }

    /// Cache key incorporating the file's modification date, or `nil` when the file
    /// cannot be stat'd (the caller falls back to an uncached read).
    private nonisolated static func resolveCacheKey(for url: URL) -> String? {
        guard let modificationDate = try? url.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate else {
            return nil
        }
        return "\(url.path)\u{1}\(modificationDate.timeIntervalSinceReferenceDate)"
    }

    /// Runs inside the task created and retained by `makeDecodeTask`, so cancelling the
    /// last waiter reaches this worker. ImageIO itself is synchronous, but cancellation
    /// checkpoints prevent a cancelled result from advancing to the next safe stage.
    private nonisolated static func decodeImage(at url: URL) async -> CGImage? {
        guard !Task.isCancelled,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        guard !Task.isCancelled else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 1
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 1
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard !Task.isCancelled else { return nil }

        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        guard !Task.isCancelled else { return nil }
        return image
    }
}
