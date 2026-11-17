#if os(macOS)
    import AVFoundation
    import CoreAudio
    import Foundation

    /// A selectable audio input device, read from the Core Audio HAL.
    ///
    /// HAL enumeration is deliberate rather than `AVCaptureDevice.DiscoverySession`.
    /// `AUAudioUnit.setDeviceID(_:)` takes an `AUAudioObjectID`, which is a Core Audio
    /// `AudioObjectID`, so the capture-device route would still need a HAL translation
    /// and only adds a hop. HAL also covers aggregate and virtual input devices, and
    /// reads device names without depending on microphone TCC state — the Settings
    /// picker must render before the user has granted the microphone permission.
    struct DictationAudioDevice: Equatable, Identifiable, Sendable {
        /// Stable across reboots and reconnects. This is the value we persist.
        let uid: String
        /// Human-readable name for the Settings picker.
        let name: String
        /// [CRITICAL] Not stable across reboots or reconnects. Never persist this;
        /// always re-resolve it from `uid` at the point of use.
        let objectID: AudioObjectID

        var id: String { uid }
    }

    enum DictationAudioDeviceError: Error, Equatable {
        case propertyReadFailed(selector: String, status: OSStatus)
        case deviceNotFound(uid: String)

        var message: String {
            switch self {
            case let .propertyReadFailed(selector, status):
                return "Audio device query failed (\(selector), status \(status))"
            case let .deviceNotFound(uid):
                return "Saved microphone is not connected (\(uid))"
            }
        }
    }

    /// The outcome of matching a saved preference against the devices present now.
    ///
    /// `unavailable` is deliberately distinct from `systemDefault`: the caller falls
    /// back to the system default either way, but only `unavailable` should tell the
    /// user their chosen microphone is missing. A silent downgrade is the bug this
    /// whole feature exists to fix.
    enum DictationAudioDeviceSelection: Equatable, Sendable {
        case systemDefault
        case device(DictationAudioDevice)
        case unavailable(uid: String)
    }

    // MARK: - Persistence

    /// Stores the chosen input device as a UID string. Absent means "System Default",
    /// which keeps today's behavior as the default for every existing user.
    enum DictationAudioDeviceStore {
        static let selectedInputDeviceUIDPreferenceKey = "com.yenchat.yen.dictationSelectedInputDeviceUID"

        static func selectedUID(defaults: UserDefaults = .standard) -> String? {
            guard let uid = defaults.string(forKey: selectedInputDeviceUIDPreferenceKey),
                  !uid.isEmpty else { return nil }
            return uid
        }

        static func setSelectedUID(_ uid: String?, defaults: UserDefaults = .standard) {
            guard let uid, !uid.isEmpty else {
                defaults.removeObject(forKey: selectedInputDeviceUIDPreferenceKey)
                return
            }
            defaults.set(uid, forKey: selectedInputDeviceUIDPreferenceKey)
        }
    }

    // MARK: - Selection

    /// Pure matching logic, split from the HAL so it is testable without hardware.
    enum DictationAudioDeviceSelector {
        static func resolve(
            preferredUID: String?,
            available: [DictationAudioDevice]
        ) -> DictationAudioDeviceSelection {
            guard let preferredUID else { return .systemDefault }
            guard let match = available.first(where: { $0.uid == preferredUID }) else {
                return .unavailable(uid: preferredUID)
            }
            return .device(match)
        }
    }

    // MARK: - Engine binding

    /// What the engine ended up recording from, and why if it is not what was asked.
    struct DictationInputDeviceBinding: Equatable, Sendable {
        /// Name of the device explicitly selected, or `nil` when the system default
        /// is in use. `nil` is the normal case, not an error.
        let deviceName: String?
        /// Non-`nil` when a saved choice could not be honored. Settings renders this;
        /// it must never be dropped, because a silent fallback to the built-in
        /// microphone is the original bug.
        let fallbackReason: String?

        static let systemDefault = Self(deviceName: nil, fallbackReason: nil)

        var didFallBack: Bool { fallbackReason != nil }
    }

    /// Applies the saved microphone choice to an engine's input node.
    ///
    /// [CRITICAL] Call this before reading `inputNode.outputFormat(forBus:)` and
    /// before installing a tap. The format is a property of the bound device, so a
    /// tap installed with the previous device's format records silence or fails.
    enum DictationInputDeviceBinder {
        private static let genericFallback = "Could not read audio devices. Using the system default microphone."

        @discardableResult
        static func apply(
            to engine: AVAudioEngine,
            defaults: UserDefaults = .standard
        ) -> DictationInputDeviceBinding {
            let selection: DictationAudioDeviceSelection
            do {
                selection = try DictationAudioDeviceResolver.currentSelection(defaults: defaults)
            } catch {
                return DictationInputDeviceBinding(deviceName: nil, fallbackReason: genericFallback)
            }

            switch selection {
            case .systemDefault:
                // Deliberately do not call setDeviceID. Leaving the input node alone
                // keeps macOS tracking the system default as it changes, which is
                // exactly what "System Default" should mean.
                return .systemDefault

            case .unavailable:
                return DictationInputDeviceBinding(
                    deviceName: nil,
                    fallbackReason: "Your selected microphone is not connected. Using the system default microphone."
                )

            case let .device(device):
                return bind(device, on: engine)
            }
        }

        private static func bind(
            _ device: DictationAudioDevice,
            on engine: AVAudioEngine
        ) -> DictationInputDeviceBinding {
            let unit = engine.inputNode.auAudioUnit
            let fallback = DictationInputDeviceBinding(
                deviceName: nil,
                fallbackReason: "Could not switch to \(device.name). Using the system default microphone."
            )

            do {
                try unit.setDeviceID(device.objectID)
            } catch {
                return fallback
            }

            // Confirm with a positive read. A non-throwing `setDeviceID` is not proof
            // the unit actually moved, and recording from the wrong microphone while
            // reporting success is the exact failure this feature exists to fix.
            guard unit.deviceID == device.objectID else { return fallback }

            return DictationInputDeviceBinding(deviceName: device.name, fallbackReason: nil)
        }
    }

    // MARK: - HAL

    enum DictationAudioDeviceResolver {
        private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

        /// Every HAL device that has at least one input channel.
        static func inputDevices() throws -> [DictationAudioDevice] {
            try deviceIDs()
                .filter { hasInputChannels($0) }
                .compactMap { objectID in
                    guard let uid = stringProperty(kAudioDevicePropertyDeviceUID, on: objectID) else {
                        return nil
                    }
                    let name = stringProperty(kAudioObjectPropertyName, on: objectID) ?? uid
                    return DictationAudioDevice(uid: uid, name: name, objectID: objectID)
                }
        }

        /// Translate a persisted UID back to a live `AudioObjectID`.
        ///
        /// Returns a typed error rather than `kAudioObjectUnknown`, so a caller can
        /// never mistake "not connected" for a usable device ID of zero.
        static func objectID(forUID uid: String) throws -> AudioObjectID {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfUID = uid as CFString
            var objectID = AudioObjectID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)

            let status = withUnsafeMutablePointer(to: &cfUID) { qualifier in
                AudioObjectGetPropertyData(
                    systemObject,
                    &address,
                    UInt32(MemoryLayout<CFString>.size),
                    qualifier,
                    &size,
                    &objectID
                )
            }

            guard status == noErr else {
                throw DictationAudioDeviceError.propertyReadFailed(
                    selector: "TranslateUIDToDevice",
                    status: status
                )
            }
            guard objectID != AudioObjectID(kAudioObjectUnknown) else {
                throw DictationAudioDeviceError.deviceNotFound(uid: uid)
            }
            return objectID
        }

        /// The device `AVAudioInputNode` would bind to on its own. Used to label the
        /// "System Default" row, not to drive capture.
        static func defaultInputDeviceID() throws -> AudioObjectID {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var objectID = AudioObjectID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &objectID)

            guard status == noErr else {
                throw DictationAudioDeviceError.propertyReadFailed(
                    selector: "DefaultInputDevice",
                    status: status
                )
            }
            return objectID
        }

        /// Resolve the saved preference against the devices present right now.
        static func currentSelection(
            defaults: UserDefaults = .standard
        ) throws -> DictationAudioDeviceSelection {
            DictationAudioDeviceSelector.resolve(
                preferredUID: DictationAudioDeviceStore.selectedUID(defaults: defaults),
                available: try inputDevices()
            )
        }

        // MARK: Private

        private static func deviceIDs() throws -> [AudioObjectID] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var size: UInt32 = 0
            let sizeStatus = AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size)
            guard sizeStatus == noErr else {
                throw DictationAudioDeviceError.propertyReadFailed(
                    selector: "Devices(size)",
                    status: sizeStatus
                )
            }

            let count = Int(size) / MemoryLayout<AudioObjectID>.size
            guard count > 0 else { return [] }

            var ids = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
            let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids)
            guard status == noErr else {
                throw DictationAudioDeviceError.propertyReadFailed(
                    selector: "Devices",
                    status: status
                )
            }

            // The device list can shrink between the size query and the read — unplug
            // a USB interface in that window and the tail of `ids` stays at its
            // `kAudioObjectUnknown` fill value. Trust the size the HAL reported back,
            // not the size it predicted.
            let returned = Int(size) / MemoryLayout<AudioObjectID>.size
            return Array(ids.prefix(min(returned, count)))
        }

        /// A device counts as an input if its input-scope stream configuration reports
        /// at least one channel. Output-only devices report zero and are filtered out.
        private static func hasInputChannels(_ objectID: AudioObjectID) -> Bool {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size) == noErr,
                  size >= UInt32(MemoryLayout<AudioBufferList>.size) else { return false }

            let buffer = UnsafeMutableRawPointer.allocate(
                byteCount: Int(size),
                alignment: MemoryLayout<AudioBufferList>.alignment
            )
            defer { buffer.deallocate() }

            guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, buffer) == noErr else {
                return false
            }

            let list = UnsafeMutableAudioBufferListPointer(
                buffer.assumingMemoryBound(to: AudioBufferList.self)
            )
            return list.contains { $0.mNumberChannels > 0 }
        }

        private static func stringProperty(
            _ selector: AudioObjectPropertySelector,
            on objectID: AudioObjectID
        ) -> String? {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            // The HAL returns a +1 retained CFStringRef, so read it through
            // `Unmanaged` and take the retained value. Reading straight into a
            // `CFString?` both leaks and forms a raw pointer to a reference.
            var value: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let status = withUnsafeMutablePointer(to: &value) { pointer in
                AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
            }
            guard status == noErr, let value else { return nil }

            let string = value.takeRetainedValue() as String
            return string.isEmpty ? nil : string
        }
    }
#endif
