import AVFoundation
import CoreAudio
import Foundation
import Testing
@testable import YEN

@MainActor
struct DictationAudioDeviceMonitorTests {
    @Test func startRegistersBothListeners() {
        let monitor = DictationAudioDeviceMonitor { _ in }
        defer { monitor.stop() }

        // Positive assertion. `start()` fails closed and returns false if either
        // HAL registration fails, so a true here means both are live — an
        // exception-free call would prove nothing on its own.
        #expect(monitor.start())
        #expect(monitor.isRunning)
    }

    @Test func startIsIdempotent() {
        let monitor = DictationAudioDeviceMonitor { _ in }
        defer { monitor.stop() }

        #expect(monitor.start())
        // A second start must not double-register. Duplicate registrations would
        // fire the handler twice per change and leak one on teardown, because the
        // HAL removes listeners by block identity.
        #expect(monitor.start())
        #expect(monitor.isRunning)
    }

    @Test func stopIsSafeWhenNeverStarted() {
        let monitor = DictationAudioDeviceMonitor { _ in }
        monitor.stop()
        #expect(!monitor.isRunning)
    }

    @Test func stopThenStartReRegisters() {
        let monitor = DictationAudioDeviceMonitor { _ in }
        defer { monitor.stop() }

        #expect(monitor.start())
        monitor.stop()
        #expect(!monitor.isRunning)
        #expect(monitor.start())
        #expect(monitor.isRunning)
    }

    @Test func changeCasesAreDistinct() {
        // The two properties change independently: a device appearing is not the
        // same event as the system default moving, and the picker reacts differently
        // to each. Collapsing them would lose that distinction.
        #expect(DictationAudioDeviceMonitor.Change.deviceListChanged
            != DictationAudioDeviceMonitor.Change.defaultInputChanged)
    }
}

@MainActor
struct DictationAudioEngineTapConfigurationTests {
    @Test(.enabled(if: DictationTestPermissions.microphoneGranted, "Microphone not granted; engine binding needs it and prompting would block the run"))
    func configurationObserverIsRemovedOnTeardown() throws {
        let tap = DictationAudioEngineTap()
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        try #require(format.sampleRate > 0, "No usable input device on this machine")

        tap.install(engine: engine, bufferSize: 1024, format: format) { _, _ in }

        var fired = 0
        tap.observeConfigurationChanges { fired += 1 }
        tap.teardown()

        // After teardown the observer must be gone. Posting the notification the
        // engine itself would post is the only way to prove removal actually
        // happened rather than assuming `teardown()` reached that branch.
        NotificationCenter.default.post(
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
        #expect(fired == 0)
    }

    @Test func observingWithoutAnInstalledEngineIsANoOp() {
        let tap = DictationAudioEngineTap()
        var fired = 0
        tap.observeConfigurationChanges { fired += 1 }

        NotificationCenter.default.post(
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
        #expect(fired == 0)
        #expect(!tap.isActive)
    }
}
