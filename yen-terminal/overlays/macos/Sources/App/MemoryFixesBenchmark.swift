#if DEBUG
import AppKit
import CoreGraphics
import Darwin
import OSLog

/// Runtime footprint harness for the memory-audit fixes. Launch the built Debug
/// binary with `YEN_MEMORY_FIXES_BENCHMARK=1` to run it; it drives each fixed
/// path in-process, prints one `MEMORY_FIXES_BENCHMARK_RESULT` line per scenario,
/// and terminates. Companion to `SettingsMemoryBenchmark`.
///
/// Scenarios:
///  - `background_image_cache` (M4): loads many distinct full-resolution decodes
///    through the bounded `TerminalBackgroundImageLoader` cache; footprint must
///    stay near the cost limit instead of growing linearly with image count.
///  - `merge_conflict_release` (M5): loads a large merge snapshot into the
///    process-lifetime model, then `releaseHeldState()`; footprint must drop and
///    the snapshot/preview cache must be cleared.
@MainActor
enum MemoryFixesBenchmark {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yenchat.yen",
        category: "MemoryFixesBenchmark"
    )

    private static let enableEnvironmentKey = "YEN_MEMORY_FIXES_BENCHMARK"
    private static let imageCountEnvironmentKey = "YEN_MEMORY_FIXES_BENCHMARK_IMAGES"

    static func maybeStart() {
        let environment = ProcessInfo.processInfo.environment
        guard let raw = environment[enableEnvironmentKey],
              raw == "1" || raw.lowercased() == "true" else { return }

        let imageCount = max(Int(environment[imageCountEnvironmentKey] ?? "") ?? 40, 12)

        Task { @MainActor in
            await pause(milliseconds: 250)
            logger.info("memory-fixes-benchmark starting images=\(imageCount)")
            await runBackgroundImageCacheScenario(imageCount: imageCount)
            await runMergeConflictReleaseScenario()
            logger.info("memory-fixes-benchmark completed")
            NSApp.terminate(nil)
        }
    }

    // MARK: - M4: background-image cache bound

    private static func runBackgroundImageCacheScenario(imageCount: Int) async {
        let loader = TerminalBackgroundImageLoader(
            cacheKeyResolver: { $0.path },
            decoder: { _ in makeLargeBenchmarkImage() }
        )

        let start = footprintBytes()
        for index in 0..<imageCount {
            _ = await loader.image(
                at: URL(fileURLWithPath: "/tmp/yen-mem-benchmark-\(index).png")
            )
        }
        let end = footprintBytes()
        _ = loader // keep the cache alive across the measurement

        printResult(
            scenario: "background_image_cache",
            start: start,
            end: end,
            extra: "distinct_images=\(imageCount) image_bytes=\(benchmarkImageByteCost)"
                + " count_limit=\(loader._testCacheCountLimit) cost_limit=\(loader._testCacheTotalCostLimit)"
        )
    }

    // MARK: - M5: merge-conflict release-on-close

    private static func runMergeConflictReleaseScenario() async {
        let runner = BenchmarkMergeRunner(snapshot: makeLargeMergeSnapshot())
        let model = MergeConflictResolutionModel(runner: runner)

        model.prepareForPresentation(workingDirectory: benchmarkRepoRoot)
        model.requestLoad()
        for _ in 0..<300 {
            if !model.isLoading, model.snapshot != nil { break }
            await pause(milliseconds: 10)
        }

        let held = footprintBytes()
        let didHoldSnapshot = model.snapshot != nil

        model.releaseHeldState()
        await pause(milliseconds: 50)
        let released = footprintBytes()
        let didReleaseSnapshot = model.snapshot == nil

        printResult(
            scenario: "merge_conflict_release",
            start: held,
            end: released,
            extra: "held_snapshot=\(didHoldSnapshot) released_snapshot=\(didReleaseSnapshot)"
        )
    }

    // MARK: - Reporting

    private static func printResult(scenario: String, start: UInt64, end: UInt64, extra: String) {
        print(
            "MEMORY_FIXES_BENCHMARK_RESULT scenario=\(scenario)"
                + " footprint_start=\(start) footprint_end=\(end)"
                + " footprint_delta=\(Int64(end) - Int64(start)) \(extra)"
        )
    }

    private static func pause(milliseconds: Int) async {
        try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }

    private static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), pointer, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

// MARK: - File-scoped (nonisolated) fixtures

private let benchmarkImageSide = 2048
private let benchmarkImageByteCost = benchmarkImageSide * benchmarkImageSide * 4
private let benchmarkRepoRoot = "/tmp/yen-mem-benchmark-repo"

/// A full-resolution decode (~16 MB at 2048x2048) so the cache bound is visible
/// in the footprint delta rather than lost in noise.
private func makeLargeBenchmarkImage() -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: benchmarkImageSide,
        height: benchmarkImageSide,
        bitsPerComponent: 8,
        bytesPerRow: benchmarkImageSide * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: benchmarkImageSide, height: benchmarkImageSide))
    return context.makeImage()
}

private func makeLargeMergeSnapshot() -> MergeConflictSnapshot {
    let bigLines = (0..<400).map { "line-\($0)-" + String(repeating: "x", count: 80) }
    let files = (0..<30).map { fileIndex -> MergeConflictFileSnapshot in
        let sections = (0..<4).map { hunkIndex -> MergeConflictFileSection in
            .conflict(
                MergeConflictHunk(
                    id: "f\(fileIndex)-h\(hunkIndex)",
                    index: hunkIndex,
                    startLine: hunkIndex * 500,
                    oursHeader: "<<<<<<< HEAD",
                    baseHeader: nil,
                    theirsHeader: ">>>>>>> feature",
                    oursLines: bigLines,
                    baseLines: nil,
                    theirsLines: bigLines,
                    markerLines: bigLines
                )
            )
        }
        return MergeConflictFileSnapshot(
            path: "src/file\(fileIndex).swift",
            sections: sections,
            unsupportedReason: nil
        )
    }
    return MergeConflictSnapshot(repoRoot: benchmarkRepoRoot, files: files)
}

private struct BenchmarkMergeRunner: MergeConflictRunning {
    let snapshot: MergeConflictSnapshot

    func resolveRepositoryRoot(for workingDirectory: String?) async throws -> String? {
        snapshot.repoRoot
    }

    func loadSnapshot(repoRoot: String) async throws -> MergeConflictSnapshot {
        snapshot
    }

    func recordChoice(request: MergeConflictChoiceRequest) throws {}

    func markResolved(request: MergeConflictResolveRequest) async throws -> MergeConflictSnapshot {
        snapshot
    }
}
#endif
