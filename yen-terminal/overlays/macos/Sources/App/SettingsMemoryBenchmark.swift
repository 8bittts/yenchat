#if DEBUG
import AppKit
import Darwin
import OSLog

@MainActor
enum SettingsMemoryBenchmark {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yenchat.yen",
        category: "SettingsMemoryBenchmark"
    )

    private static let modeEnvironmentKey = "YEN_SETTINGS_MEMORY_BENCHMARK_MODE"
    private static let iterationsEnvironmentKey = "YEN_SETTINGS_MEMORY_BENCHMARK_ITERATIONS"
    private static let pauseMillisecondsEnvironmentKey = "YEN_SETTINGS_MEMORY_BENCHMARK_PAUSE_MS"

    enum Mode: String {
        case release = "release"
        case retain = "retain"

        var windowCloseModeOverride: SettingsController.TestWindowCloseMemoryMode {
            switch self {
            case .release:
                .releaseWindowGraph
            case .retain:
                .retainWindowGraph
            }
        }
    }

    @MainActor
    private struct PreferenceSnapshot {
        let copyOnSelect: Bool
        let splitPaneLabelsEnabled: Bool
        let tabSidebarEnabled: Bool
        let tabSidebarPresentationMode: TabSidebarPresentationMode
        let tabSidebarPersistentVisible: Bool
        let windowBorderEnabled: Bool
        let windowBorderColorMode: WindowBorderColorMode

        init(controller: SettingsController) {
            copyOnSelect = controller.copyOnSelect
            splitPaneLabelsEnabled = controller.splitPaneLabelsEnabled
            tabSidebarEnabled = controller.tabSidebarEnabled
            tabSidebarPresentationMode = controller.tabSidebarPresentationMode
            tabSidebarPersistentVisible = TabSidebarController.persistentVisible
            windowBorderEnabled = controller.windowBorderEnabled
            windowBorderColorMode = controller.windowBorderColorMode
        }

        func restore(on controller: SettingsController) {
            controller.copyOnSelect = copyOnSelect
            controller.splitPaneLabelsEnabled = splitPaneLabelsEnabled
            controller.tabSidebarEnabled = tabSidebarEnabled
            controller.tabSidebarPresentationMode = tabSidebarPresentationMode
            TabSidebarController.shared.setPersistentVisiblePreference(tabSidebarPersistentVisible)
            controller.windowBorderEnabled = windowBorderEnabled
            controller.windowBorderColorMode = windowBorderColorMode
        }
    }

    @MainActor
    private struct PreferenceState {
        let copyOnSelect: Bool
        let splitPaneLabelsEnabled: Bool
        let tabSidebarEnabled: Bool
        let tabSidebarPresentationMode: TabSidebarPresentationMode
        let tabSidebarPersistentVisible: Bool
        let windowBorderEnabled: Bool
        let windowBorderColorMode: WindowBorderColorMode

        init(controller: SettingsController) {
            copyOnSelect = controller.copyOnSelect
            splitPaneLabelsEnabled = controller.splitPaneLabelsEnabled
            tabSidebarEnabled = controller.tabSidebarEnabled
            tabSidebarPresentationMode = controller.tabSidebarPresentationMode
            tabSidebarPersistentVisible = TabSidebarController.persistentVisible
            windowBorderEnabled = controller.windowBorderEnabled
            windowBorderColorMode = controller.windowBorderColorMode
        }
    }

    private struct MemorySample {
        let residentBytes: UInt64
        let footprintBytes: UInt64
    }

    static func maybeStart() {
        let environment = ProcessInfo.processInfo.environment
        guard let rawMode = environment[modeEnvironmentKey],
              let mode = Mode(rawValue: rawMode.lowercased()) else { return }

        let iterations = max(Int(environment[iterationsEnvironmentKey] ?? "") ?? 30, 1)
        let pauseMilliseconds = max(Int(environment[pauseMillisecondsEnvironmentKey] ?? "") ?? 35, 5)

        Task { @MainActor in
            await pause(milliseconds: 250)
            await run(mode: mode, iterations: iterations, pauseMilliseconds: pauseMilliseconds)
        }
    }

    private static func run(mode: Mode, iterations: Int, pauseMilliseconds: Int) async {
        let settings = SettingsController.shared
        let onboarding = OnboardingController.shared
        let about = AboutController.shared
        let snapshot = PreferenceSnapshot(controller: settings)

        defer {
            settings.hide()
            settings._testResetWindowState()
            SettingsController._testSetWindowCloseMemoryModeOverride(nil)
            snapshot.restore(on: settings)
            about.hide()
            about._testResetState()
            onboarding._testResetState()
        }

        SettingsController._testSetWindowCloseMemoryModeOverride(mode.windowCloseModeOverride)
        settings._testResetWindowState()
        about._testResetState()
        onboarding._testResetState()
        configureScenario(on: settings)

        let panes = SettingsPane.allCases
        var peakResidentBytes: UInt64 = 0
        var peakFootprintBytes: UInt64 = 0

        let startSample = captureMemorySample()
        updatePeaks(using: startSample, peakResidentBytes: &peakResidentBytes, peakFootprintBytes: &peakFootprintBytes)

        logger.info("settings-memory-benchmark starting mode=\(mode.rawValue, privacy: .public) iterations=\(iterations)")

        for _ in 0..<iterations {
            settings.show(pane: .appearance)
            await pause(milliseconds: pauseMilliseconds)

            for pane in panes {
                settings.show(pane: pane)
                await pause(milliseconds: pauseMilliseconds)
                updatePeaks(
                    using: captureMemorySample(),
                    peakResidentBytes: &peakResidentBytes,
                    peakFootprintBytes: &peakFootprintBytes
                )
            }

            settings.hide()
            await pause(milliseconds: pauseMilliseconds)
            updatePeaks(
                using: captureMemorySample(),
                peakResidentBytes: &peakResidentBytes,
                peakFootprintBytes: &peakFootprintBytes
            )
        }

        let retainedWindowAfterHide = settings._testHasWindow

        about.show()
        await pause(milliseconds: pauseMilliseconds)
        let aboutWindowAvailable = about._testHasWindow
        about.hide()
        await pause(milliseconds: pauseMilliseconds)
        let aboutWindowRetainedAfterHide = about._testHasWindow

        onboarding.show()
        await pause(milliseconds: pauseMilliseconds)
        let onboardingWindowAvailable = onboarding._testHasWindow
        onboarding.dismiss()
        await pause(milliseconds: pauseMilliseconds)
        let onboardingWindowRetainedAfterHide = onboarding._testHasWindow

        let preReloadState = PreferenceState(controller: settings)

        NotificationCenter.default.post(name: .yenConfigDidReload, object: nil)
        await pause(milliseconds: pauseMilliseconds)

        let endSample = captureMemorySample()
        updatePeaks(using: endSample, peakResidentBytes: &peakResidentBytes, peakFootprintBytes: &peakFootprintBytes)

        print(
            benchmarkSummary(
                mode: mode,
                iterations: iterations,
                pauseMilliseconds: pauseMilliseconds,
                startSample: startSample,
                endSample: endSample,
                peakResidentBytes: peakResidentBytes,
                peakFootprintBytes: peakFootprintBytes,
                preReloadState: preReloadState,
                retainedWindowAfterHide: retainedWindowAfterHide,
                aboutWindowAvailable: aboutWindowAvailable,
                aboutWindowRetainedAfterHide: aboutWindowRetainedAfterHide,
                onboardingWindowAvailable: onboardingWindowAvailable,
                onboardingWindowRetainedAfterHide: onboardingWindowRetainedAfterHide
            )
        )

        logger.info("settings-memory-benchmark completed mode=\(mode.rawValue, privacy: .public)")
        NSApp.terminate(nil)
    }

    private static func configureScenario(on controller: SettingsController) {
        controller.copyOnSelect = false
        controller.splitPaneLabelsEnabled = true
        controller.tabSidebarEnabled = true
        controller.tabSidebarPresentationMode = .persistent
        TabSidebarController.shared.setPersistentVisiblePreference(true)
        controller.windowBorderEnabled = true
        controller.windowBorderColorMode = .manual
    }

    private static func benchmarkSummary(
        mode: Mode,
        iterations: Int,
        pauseMilliseconds: Int,
        startSample: MemorySample?,
        endSample: MemorySample?,
        peakResidentBytes: UInt64,
        peakFootprintBytes: UInt64,
        preReloadState: PreferenceState,
        retainedWindowAfterHide: Bool,
        aboutWindowAvailable: Bool,
        aboutWindowRetainedAfterHide: Bool,
        onboardingWindowAvailable: Bool,
        onboardingWindowRetainedAfterHide: Bool
    ) -> String {
        let residentStart = startSample?.residentBytes ?? 0
        let residentEnd = endSample?.residentBytes ?? 0
        let footprintStart = startSample?.footprintBytes ?? 0
        let footprintEnd = endSample?.footprintBytes ?? 0

        return [
            "SETTINGS_MEMORY_BENCHMARK_RESULT",
            "mode=\(mode.rawValue)",
            "iterations=\(iterations)",
            "pause_ms=\(pauseMilliseconds)",
            "resident_start=\(residentStart)",
            "resident_end=\(residentEnd)",
            "resident_delta=\(Int64(residentEnd) - Int64(residentStart))",
            "resident_peak=\(peakResidentBytes)",
            "footprint_start=\(footprintStart)",
            "footprint_end=\(footprintEnd)",
            "footprint_delta=\(Int64(footprintEnd) - Int64(footprintStart))",
            "footprint_peak=\(peakFootprintBytes)",
            "window_retained_after_hide=\(retainedWindowAfterHide)",
            "copy_on_select=\(preReloadState.copyOnSelect)",
            "split_labels_enabled=\(preReloadState.splitPaneLabelsEnabled)",
            "tab_sidebar_enabled=\(preReloadState.tabSidebarEnabled)",
            "tab_sidebar_mode=\(preReloadState.tabSidebarPresentationMode.rawValue)",
            "tab_sidebar_persistent_visible=\(preReloadState.tabSidebarPersistentVisible)",
            "window_border_enabled=\(preReloadState.windowBorderEnabled)",
            "window_border_color_mode=\(preReloadState.windowBorderColorMode.rawValue)",
            "about_window_available=\(aboutWindowAvailable)",
            "about_window_retained_after_hide=\(aboutWindowRetainedAfterHide)",
            "onboarding_window_available=\(onboardingWindowAvailable)",
            "onboarding_window_retained_after_hide=\(onboardingWindowRetainedAfterHide)",
        ].joined(separator: " ")
    }

    private static func pause(milliseconds: Int) async {
        try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }

    private static func updatePeaks(
        using sample: MemorySample?,
        peakResidentBytes: inout UInt64,
        peakFootprintBytes: inout UInt64
    ) {
        guard let sample else { return }
        peakResidentBytes = max(peakResidentBytes, sample.residentBytes)
        peakFootprintBytes = max(peakFootprintBytes, sample.footprintBytes)
    }

    private static func captureMemorySample() -> MemorySample? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), pointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        return MemorySample(
            residentBytes: info.resident_size,
            footprintBytes: info.phys_footprint
        )
    }
}
#endif
