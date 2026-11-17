import CoreAudio
import Foundation
import Testing
@testable import YEN

struct DictationInputDeviceOptionsTests {
    private func device(_ uid: String, _ name: String, _ objectID: AudioObjectID = 1) -> DictationAudioDevice {
        DictationAudioDevice(uid: uid, name: name, objectID: objectID)
    }

    private let builtIn = DictationAudioDevice(
        uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone", objectID: 71
    )
    private let external = DictationAudioDevice(
        uid: "usb-mic-01", name: "Shure MV7", objectID: 42
    )

    // MARK: - Ordering and contents

    @Test func systemDefaultIsAlwaysFirst() {
        let options = DictationInputDeviceOptionsBuilder.makeOptions(
            devices: [builtIn, external],
            selectedUID: nil,
            defaultDeviceName: nil
        )
        #expect(options.first?.isSystemDefault == true)
        #expect(options.count == 3)
    }

    @Test func connectedDevicesKeepHALOrder() {
        let options = DictationInputDeviceOptionsBuilder.makeOptions(
            devices: [external, builtIn],
            selectedUID: nil,
            defaultDeviceName: nil
        )
        #expect(options.map(\.identifier) == ["", "usb-mic-01", "BuiltInMicrophoneDevice"])
    }

    @Test func emptyDeviceListStillOffersSystemDefault() {
        let options = DictationInputDeviceOptionsBuilder.makeOptions(
            devices: [],
            selectedUID: nil,
            defaultDeviceName: nil
        )
        #expect(options.count == 1)
        #expect(options[0].isSystemDefault)
    }

    // MARK: - System Default labelling

    @Test func systemDefaultLabelNamesTheResolvedDevice() {
        let options = DictationInputDeviceOptionsBuilder.makeOptions(
            devices: [builtIn],
            selectedUID: nil,
            defaultDeviceName: "MacBook Pro Microphone"
        )
        // Naming the resolved device is the point: the original report was a user who
        // could not tell which microphone "default" meant.
        #expect(options[0].displayName == "System Default (MacBook Pro Microphone)")
    }

    @Test func systemDefaultLabelStaysPlainWithoutAResolvedName() {
        #expect(DictationInputDeviceOptionsBuilder.systemDefaultLabel(resolvingTo: nil)
            == "System Default")
        #expect(DictationInputDeviceOptionsBuilder.systemDefaultLabel(resolvingTo: "")
            == "System Default")
    }

    // MARK: - Disconnected saved device

    @Test func savedButMissingDeviceGetsItsOwnRow() {
        let options = DictationInputDeviceOptionsBuilder.makeOptions(
            devices: [builtIn],
            selectedUID: "usb-mic-01",
            defaultDeviceName: nil
        )
        #expect(options.count == 3)
        #expect(options.last?.identifier == "usb-mic-01")
        #expect(options.last?.isDisconnected == true)
        #expect(options.last?.displayName.contains("not connected") == true)
    }

    @Test func savedAndPresentDeviceIsNotDuplicated() {
        let options = DictationInputDeviceOptionsBuilder.makeOptions(
            devices: [builtIn, external],
            selectedUID: "usb-mic-01",
            defaultDeviceName: nil
        )
        #expect(options.count == 3)
        #expect(options.filter { $0.identifier == "usb-mic-01" }.count == 1)
        #expect(options.allSatisfy { !$0.isDisconnected })
    }

    @Test func emptySelectionDoesNotCreateAPhantomDisconnectedRow() {
        let options = DictationInputDeviceOptionsBuilder.makeOptions(
            devices: [builtIn],
            selectedUID: "",
            defaultDeviceName: nil
        )
        #expect(options.count == 2)
        #expect(options.allSatisfy { !$0.isDisconnected })
    }

    // MARK: - Selection round-trip

    @Test func selectedIdentifierMapsAbsentPreferenceToSystemDefault() {
        #expect(DictationInputDeviceOptionsBuilder.selectedIdentifier(for: nil)
            == DictationInputDeviceOption.systemDefaultIdentifier)
        #expect(DictationInputDeviceOptionsBuilder.selectedIdentifier(for: "")
            == DictationInputDeviceOption.systemDefaultIdentifier)
    }

    @Test func selectedIdentifierPassesThroughARealUID() {
        #expect(DictationInputDeviceOptionsBuilder.selectedIdentifier(for: "usb-mic-01")
            == "usb-mic-01")
    }

    @Test func systemDefaultSentinelRoundTripsThroughTheStore() throws {
        let suite = "com.yenchat.yen.tests.dictationInputDeviceOptions.roundTrip"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        // Selecting the System Default row writes the sentinel, which the store must
        // read back as "no preference" — otherwise picking System Default would
        // persist an empty UID that never resolves to a device.
        DictationAudioDeviceStore.setSelectedUID(
            DictationInputDeviceOption.systemDefaultIdentifier, defaults: defaults
        )
        #expect(DictationAudioDeviceStore.selectedUID(defaults: defaults) == nil)

        let options = DictationInputDeviceOptionsBuilder.makeOptions(
            devices: [builtIn],
            selectedUID: DictationAudioDeviceStore.selectedUID(defaults: defaults),
            defaultDeviceName: nil
        )
        #expect(options.count == 2)
    }

    @Test func everyOptionIdentifierIsUnique() {
        let options = DictationInputDeviceOptionsBuilder.makeOptions(
            devices: [builtIn, external],
            selectedUID: "missing-mic",
            defaultDeviceName: "MacBook Pro Microphone"
        )
        // SwiftUI Picker tags and ForEach ids must be unique or rows silently collapse.
        let ids = options.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
