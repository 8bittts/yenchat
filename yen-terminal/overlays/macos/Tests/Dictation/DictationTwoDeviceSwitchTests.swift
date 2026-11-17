import AVFoundation
import ApplicationServices
import CoreAudio
import Foundation
import Testing
@testable import YEN

/// Two-device coverage for the microphone picker.
///
/// Every other dictation test on a single-microphone machine binds the built-in
/// device to itself, which cannot fail: `setDeviceID` is a no-op when the unit is
/// already on that device. The reported bug was specifically that YEN would not
/// move OFF the built-in microphone, so the untested path was the only one that
/// mattered.
///
/// A private aggregate device supplies a real second input device without any
/// hardware. It is a genuine Core Audio device with its own `AudioObjectID`, UID,
/// and input stream, so `setDeviceID` has to perform an actual switch. Private
/// means it is visible only to this process, so a crashed test cannot leave a
/// stray device in the user's Sound settings.
@MainActor
struct DictationTwoDeviceSwitchTests {
    private static let aggregateUID = "com.yenchat.yen.tests.aggregate"

    /// Creates a private aggregate device wrapping the current default input.
    /// Returns nil when the machine has no input device to wrap at all.
    private func makeAggregate(over subDeviceUID: String) -> AudioDeviceID? {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "YEN Test Aggregate",
            kAudioAggregateDeviceUIDKey: Self.aggregateUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: subDeviceUID]],
            // Private: visible to this process only, so a failed test cannot pollute
            // the user's real audio device list.
            kAudioAggregateDeviceIsPrivateKey: 1,
        ]
        var deviceID = AudioDeviceID(0)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID)
        guard status == noErr, deviceID != AudioDeviceID(0) else { return nil }
        return deviceID
    }

    private func destroy(_ deviceID: AudioDeviceID) {
        _ = AudioHardwareDestroyAggregateDevice(deviceID)
    }

    /// Wait for a newly created device to reach THIS process's HAL client.
    ///
    /// `AudioHardwareCreateAggregateDevice` returns before the device is visible to
    /// the calling process's cached device list; querying immediately yields
    /// "no object with given ID". Spin the run loop so the HAL change notification
    /// is delivered, rather than sleeping blindly.
    @discardableResult
    private func waitForDevice(uid: String, present: Bool, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let devices = (try? DictationAudioDeviceResolver.inputDevices()) ?? []
            if devices.contains(where: { $0.uid == uid }) == present { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return false
    }

    /// Create the aggregate and block until it is actually visible here.
    private func makeVisibleAggregate(over subDeviceUID: String) throws -> AudioDeviceID {
        let deviceID = try #require(
            makeAggregate(over: subDeviceUID),
            "Could not create a private aggregate device"
        )
        guard waitForDevice(uid: Self.aggregateUID, present: true) else {
            destroy(deviceID)
            Issue.record("Aggregate device never became visible to this process")
            throw CancellationError()
        }
        return deviceID
    }

    /// Report the three dictation permissions up front.
    ///
    /// These tests only enumerate devices and bind an engine, which needs no grant,
    /// so a missing permission must NOT fail them. But when one of these does fail
    /// on a machine where a permission is off, the cause has to be visible in the
    /// output rather than guessed at, because a denied microphone can make Core
    /// Audio behave in ways that look like a device bug.
    private func isolatedDefaults(_ label: String) throws -> UserDefaults {
        let suite = "com.yenchat.yen.tests.twoDevice.\(label)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// The whole feature in one test: enumerate two devices, bind each, and confirm
    /// the audio unit actually moved between them.
    @Test(.enabled(if: DictationTestPermissions.microphoneGranted, "Microphone not granted; engine binding needs it and prompting would block the run"))
    func bindingSwitchesBetweenTwoDistinctDevices() throws {
        let existing = try DictationAudioDeviceResolver.inputDevices()
        let base = try #require(
            existing.first,
            "No input device to aggregate (\(DictationTestPermissions.summary))"
        )

        let aggregateID = try makeVisibleAggregate(over: base.uid)
        defer { destroy(aggregateID) }

        let devices = try DictationAudioDeviceResolver.inputDevices()
        #expect(devices.count >= 2, "Expected built-in + aggregate (\(DictationTestPermissions.summary))")
        let aggregate = try #require(devices.first { $0.uid == Self.aggregateUID })
        let builtIn = try #require(devices.first { $0.uid == base.uid })
        #expect(aggregate.objectID != builtIn.objectID)

        let defaults = try isolatedDefaults("switch")
        let engine = AVAudioEngine()

        // Bind the aggregate. This is a real move away from the default device.
        DictationAudioDeviceStore.setSelectedUID(aggregate.uid, defaults: defaults)
        let toAggregate = DictationInputDeviceBinder.apply(to: engine, defaults: defaults)
        #expect(!toAggregate.didFallBack)
        #expect(toAggregate.deviceName == aggregate.name)
        #expect(engine.inputNode.auAudioUnit.deviceID == aggregate.objectID)

        // Now move BACK to the built-in on the same engine. A binder that only ever
        // set the device once, or that silently kept the first selection, passes
        // every single-device test and fails here.
        DictationAudioDeviceStore.setSelectedUID(builtIn.uid, defaults: defaults)
        let toBuiltIn = DictationInputDeviceBinder.apply(to: engine, defaults: defaults)
        #expect(!toBuiltIn.didFallBack)
        #expect(toBuiltIn.deviceName == builtIn.name)
        #expect(engine.inputNode.auAudioUnit.deviceID == builtIn.objectID)
        #expect(engine.inputNode.auAudioUnit.deviceID != aggregate.objectID)
    }

    /// The format must be readable after switching, because both recognizers reject
    /// a zero sample rate as `noAudioInput` immediately after binding.
    @Test(.enabled(if: DictationTestPermissions.microphoneGranted, "Microphone not granted; engine binding needs it and prompting would block the run"))
    func formatRemainsUsableAfterSwitchingDevices() throws {
        let existing = try DictationAudioDeviceResolver.inputDevices()
        let base = try #require(existing.first, "No input device on this machine to aggregate")
        let aggregateID = try makeVisibleAggregate(over: base.uid)
        defer { destroy(aggregateID) }

        let devices = try DictationAudioDeviceResolver.inputDevices()
        let aggregate = try #require(devices.first { $0.uid == Self.aggregateUID })

        let defaults = try isolatedDefaults("format")
        DictationAudioDeviceStore.setSelectedUID(aggregate.uid, defaults: defaults)

        let engine = AVAudioEngine()
        DictationInputDeviceBinder.apply(to: engine, defaults: defaults)
        #expect(engine.inputNode.outputFormat(forBus: 0).sampleRate > 0)
    }

    /// Disconnecting the selected device is the other path a single-device machine
    /// cannot reach. Destroying the aggregate is a real disconnect.
    @Test(.enabled(if: DictationTestPermissions.microphoneGranted, "Microphone not granted; engine binding needs it and prompting would block the run"))
    func disconnectingTheSelectedDeviceFallsBackAndSaysWhy() throws {
        let existing = try DictationAudioDeviceResolver.inputDevices()
        let base = try #require(existing.first, "No input device on this machine to aggregate")
        let aggregateID = try makeVisibleAggregate(over: base.uid)

        let defaults = try isolatedDefaults("disconnect")
        DictationAudioDeviceStore.setSelectedUID(Self.aggregateUID, defaults: defaults)

        // Present: resolves to the device.
        let before = try DictationAudioDeviceResolver.currentSelection(defaults: defaults)
        #expect(before != .systemDefault)
        #expect(before != .unavailable(uid: Self.aggregateUID))

        destroy(aggregateID)
        #expect(waitForDevice(uid: Self.aggregateUID, present: false))

        // Gone: resolves to unavailable, NOT systemDefault. The distinction is what
        // lets Settings tell the user their microphone is missing.
        let after = try DictationAudioDeviceResolver.currentSelection(defaults: defaults)
        #expect(after == .unavailable(uid: Self.aggregateUID))

        let binding = DictationInputDeviceBinder.apply(to: AVAudioEngine(), defaults: defaults)
        #expect(binding.didFallBack)
        let reason = try #require(binding.fallbackReason)
        #expect(reason.contains("not connected"))

        // The saved choice must still be offered so the user can see what is missing.
        let options = DictationInputDeviceOptionsBuilder.makeOptions(
            devices: try DictationAudioDeviceResolver.inputDevices(),
            selectedUID: DictationAudioDeviceStore.selectedUID(defaults: defaults),
            defaultDeviceName: nil
        )
        let missingRow = try #require(options.first { $0.identifier == Self.aggregateUID })
        #expect(missingRow.isDisconnected)
    }

    /// The picker must list both devices plus System Default, with unique ids.
    @Test func pickerListsBothDevicesPlusSystemDefault() throws {
        let existing = try DictationAudioDeviceResolver.inputDevices()
        let base = try #require(existing.first, "No input device on this machine to aggregate")
        let aggregateID = try makeVisibleAggregate(over: base.uid)
        defer { destroy(aggregateID) }

        let devices = try DictationAudioDeviceResolver.inputDevices()
        let options = DictationInputDeviceOptionsBuilder.makeOptions(
            devices: devices,
            selectedUID: nil,
            defaultDeviceName: base.name
        )

        #expect(options.count == devices.count + 1)
        #expect(options[0].isSystemDefault)
        #expect(options[0].displayName.contains(base.name))
        #expect(options.contains { $0.identifier == Self.aggregateUID })

        let ids = options.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
