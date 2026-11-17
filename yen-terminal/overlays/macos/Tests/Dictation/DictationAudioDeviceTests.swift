import AVFoundation
import CoreAudio
import Foundation
import Testing
@testable import YEN

struct DictationAudioDeviceTests {
    private func device(_ uid: String, _ name: String, _ objectID: AudioObjectID = 1) -> DictationAudioDevice {
        DictationAudioDevice(uid: uid, name: name, objectID: objectID)
    }

    private func isolatedDefaults(_ label: String) throws -> UserDefaults {
        let suite = "com.yenchat.yen.tests.dictationAudioDevice.\(label)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - Selection

    @Test func absentPreferenceResolvesToSystemDefault() {
        let selection = DictationAudioDeviceSelector.resolve(
            preferredUID: nil,
            available: [device("built-in", "MacBook Pro Microphone")]
        )
        #expect(selection == .systemDefault)
    }

    @Test func savedPreferenceResolvesToThatDevice() {
        let external = device("usb-mic-01", "Shure MV7", 42)
        let selection = DictationAudioDeviceSelector.resolve(
            preferredUID: "usb-mic-01",
            available: [device("built-in", "MacBook Pro Microphone"), external]
        )
        #expect(selection == .device(external))
    }

    @Test func disconnectedPreferenceIsUnavailableNotSystemDefault() {
        let selection = DictationAudioDeviceSelector.resolve(
            preferredUID: "usb-mic-01",
            available: [device("built-in", "MacBook Pro Microphone")]
        )
        // The caller still falls back to the system default, but it must be able to
        // tell the user why. Collapsing this into `.systemDefault` would reintroduce
        // the exact silent downgrade this feature fixes.
        #expect(selection == .unavailable(uid: "usb-mic-01"))
    }

    @Test func emptyDeviceListWithAPreferenceIsUnavailable() {
        let selection = DictationAudioDeviceSelector.resolve(
            preferredUID: "usb-mic-01",
            available: []
        )
        #expect(selection == .unavailable(uid: "usb-mic-01"))
    }

    @Test func emptyDeviceListWithoutAPreferenceIsSystemDefault() {
        let selection = DictationAudioDeviceSelector.resolve(preferredUID: nil, available: [])
        #expect(selection == .systemDefault)
    }

    // MARK: - Persistence

    @Test func storeRoundTripsAUID() throws {
        let defaults = try isolatedDefaults("roundTrip")
        #expect(DictationAudioDeviceStore.selectedUID(defaults: defaults) == nil)

        DictationAudioDeviceStore.setSelectedUID("usb-mic-01", defaults: defaults)
        #expect(DictationAudioDeviceStore.selectedUID(defaults: defaults) == "usb-mic-01")
    }

    @Test func storeClearsOnNil() throws {
        let defaults = try isolatedDefaults("clearNil")
        DictationAudioDeviceStore.setSelectedUID("usb-mic-01", defaults: defaults)
        DictationAudioDeviceStore.setSelectedUID(nil, defaults: defaults)
        #expect(DictationAudioDeviceStore.selectedUID(defaults: defaults) == nil)
    }

    @Test func storeTreatsEmptyStringAsSystemDefault() throws {
        let defaults = try isolatedDefaults("emptyString")
        DictationAudioDeviceStore.setSelectedUID("", defaults: defaults)
        #expect(DictationAudioDeviceStore.selectedUID(defaults: defaults) == nil)

        // Also guard the read path against an empty value written by an older build.
        defaults.set("", forKey: DictationAudioDeviceStore.selectedInputDeviceUIDPreferenceKey)
        #expect(DictationAudioDeviceStore.selectedUID(defaults: defaults) == nil)
    }

    @Test func storeUsesTheProjectPreferenceKeyConvention() {
        #expect(
            DictationAudioDeviceStore.selectedInputDeviceUIDPreferenceKey
                == "com.yenchat.yen.dictationSelectedInputDeviceUID"
        )
    }

    // MARK: - Errors

    /// The HAL returns `noErr` with `kAudioObjectUnknown` (0) for a UID it does not
    /// recognize — measured, not assumed. So the explicit zero check is the only
    /// thing standing between a disconnected microphone and a device ID of 0 being
    /// handed to `setDeviceID`. Assert the exact case: a generic
    /// `DictationAudioDeviceError` match would also pass if this became a
    /// `propertyReadFailed`, which would hide that the zero guard had stopped working.
    @Test func unknownUIDTranslatesToDeviceNotFoundSpecifically() {
        #expect(throws: DictationAudioDeviceError.deviceNotFound(uid: "yen-nonexistent-device-uid")) {
            _ = try DictationAudioDeviceResolver.objectID(forUID: "yen-nonexistent-device-uid")
        }
    }

    @Test func errorMessagesAreUserReadable() {
        let notFound = DictationAudioDeviceError.deviceNotFound(uid: "usb-mic-01")
        #expect(notFound.message.contains("usb-mic-01"))

        let failed = DictationAudioDeviceError.propertyReadFailed(selector: "Devices", status: -1)
        #expect(failed.message.contains("Devices"))
    }

    // MARK: - Engine binding

    @Test(.enabled(if: DictationTestPermissions.microphoneGranted, "Microphone not granted; engine binding needs it and prompting would block the run"))
    func bindingWithNoPreferenceLeavesTheEngineOnTheSystemDefault() throws {
        let defaults = try isolatedDefaults("bindDefault")
        let engine = AVAudioEngine()
        let before = engine.inputNode.auAudioUnit.deviceID

        let binding = DictationInputDeviceBinder.apply(to: engine, defaults: defaults)

        #expect(binding == .systemDefault)
        #expect(!binding.didFallBack)
        #expect(binding.deviceName == nil)
        // "System Default" must not pin the unit to a device ID, otherwise it would
        // stop tracking the system default as the user changes it.
        #expect(engine.inputNode.auAudioUnit.deviceID == before)
    }

    @Test(.enabled(if: DictationTestPermissions.microphoneGranted, "Microphone not granted; engine binding needs it and prompting would block the run"))
    func bindingWithADisconnectedDeviceReportsAFallbackReason() throws {
        let defaults = try isolatedDefaults("bindMissing")
        DictationAudioDeviceStore.setSelectedUID("yen-nonexistent-device-uid", defaults: defaults)

        let binding = DictationInputDeviceBinder.apply(to: AVAudioEngine(), defaults: defaults)

        #expect(binding.didFallBack)
        #expect(binding.deviceName == nil)
        let reason = try #require(binding.fallbackReason)
        #expect(reason.contains("not connected"))
    }

    @Test(.enabled(if: DictationTestPermissions.microphoneGranted, "Microphone not granted; engine binding needs it and prompting would block the run"))
    func bindingARealDeviceMovesTheUnitAndReportsNoFallback() throws {
        let defaults = try isolatedDefaults("bindReal")
        let devices = try DictationAudioDeviceResolver.inputDevices()
        let target = try #require(devices.first, "No input device on this machine to bind")
        DictationAudioDeviceStore.setSelectedUID(target.uid, defaults: defaults)

        let engine = AVAudioEngine()
        let binding = DictationInputDeviceBinder.apply(to: engine, defaults: defaults)

        #expect(!binding.didFallBack)
        #expect(binding.deviceName == target.name)
        // Positive confirmation the unit actually moved, which is the whole contract.
        #expect(engine.inputNode.auAudioUnit.deviceID == target.objectID)
    }

    @Test(.enabled(if: DictationTestPermissions.microphoneGranted, "Microphone not granted; engine binding needs it and prompting would block the run"))
    func boundDeviceFormatIsReadableAfterBinding() throws {
        let defaults = try isolatedDefaults("bindFormat")
        let devices = try DictationAudioDeviceResolver.inputDevices()
        let target = try #require(devices.first, "No input device on this machine to bind")
        DictationAudioDeviceStore.setSelectedUID(target.uid, defaults: defaults)

        let engine = AVAudioEngine()
        DictationInputDeviceBinder.apply(to: engine, defaults: defaults)

        // Both recognizers guard on `sampleRate > 0` immediately after binding and
        // treat zero as `noAudioInput`. If binding left the node unusable, that guard
        // would turn a working microphone into a hard failure.
        #expect(engine.inputNode.outputFormat(forBus: 0).sampleRate > 0)
    }

    // MARK: - HAL

    /// Fail closed. The two HAL tests below iterate the device list, so they would
    /// both pass vacuously on an empty enumeration — the exact false green a broken
    /// `hasInputChannels` filter would produce. This ties the list to an independent
    /// signal: if the HAL reports a real default input device, enumeration must find
    /// at least one. A genuinely mic-less machine reports `kAudioObjectUnknown` and
    /// is correctly exempt.
    @Test func enumerationIsNonEmptyWheneverADefaultInputDeviceExists() throws {
        let defaultID = try DictationAudioDeviceResolver.defaultInputDeviceID()
        try withKnownIssue("Machine reports no default input device", isIntermittent: false) {
            try #require(defaultID != AudioObjectID(kAudioObjectUnknown))
        } when: {
            defaultID == AudioObjectID(kAudioObjectUnknown)
        }

        guard defaultID != AudioObjectID(kAudioObjectUnknown) else { return }
        let devices = try DictationAudioDeviceResolver.inputDevices()
        #expect(!devices.isEmpty)
        #expect(devices.contains { $0.objectID == defaultID })
    }

    @Test func inputDevicesAreWellFormedAndUnique() throws {
        let devices = try DictationAudioDeviceResolver.inputDevices()

        // A CI or headless machine can legitimately have zero input devices, so the
        // count is not asserted. Every device that IS returned must be well formed.
        for device in devices {
            #expect(!device.uid.isEmpty)
            #expect(!device.name.isEmpty)
            #expect(device.objectID != AudioObjectID(kAudioObjectUnknown))
        }

        let uids = devices.map(\.uid)
        #expect(Set(uids).count == uids.count)
    }

    @Test func enumeratedDeviceUIDsTranslateBackToTheSameObjectID() throws {
        for device in try DictationAudioDeviceResolver.inputDevices() {
            let resolved = try DictationAudioDeviceResolver.objectID(forUID: device.uid)
            #expect(resolved == device.objectID)
        }
    }
}
