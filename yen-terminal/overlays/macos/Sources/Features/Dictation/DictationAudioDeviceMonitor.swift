#if os(macOS)
    import CoreAudio
    import Foundation

    /// Watches the Core Audio HAL for input-device changes.
    ///
    /// Two separate properties matter and they change independently:
    /// `kAudioHardwarePropertyDevices` fires when a microphone is plugged in or
    /// pulled out, and `kAudioHardwarePropertyDefaultInputDevice` fires when the
    /// system default moves — including when macOS silently reverts to the built-in
    /// microphone after a USB or Bluetooth device drops. The Settings picker needs
    /// both: one to keep its list current, the other to keep the "System Default" row
    /// honest about which device it actually resolves to.
    final class DictationAudioDeviceMonitor {
        enum Change: Equatable, Sendable {
            /// A device appeared or disappeared.
            case deviceListChanged
            /// The system default input device moved.
            case defaultInputChanged
        }

        private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

        private static let deviceListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        private static let defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        private let onChange: @MainActor (Change) -> Void

        /// The HAL matches listeners by block identity on removal, so the exact block
        /// objects passed to `Add` must be retained and passed back to `Remove`.
        /// Rebuilding an equivalent closure at teardown leaks the registration.
        private var deviceListBlock: AudioObjectPropertyListenerBlock?
        private var defaultInputBlock: AudioObjectPropertyListenerBlock?

        private(set) var isRunning = false

        init(onChange: @escaping @MainActor (Change) -> Void) {
            self.onChange = onChange
        }

        deinit {
            // Cannot call `stop()` here — it is main-actor-free but the blocks must
            // still be unregistered or the HAL calls into a deallocated object.
            removeListeners()
        }

        /// Register both listeners. Safe to call repeatedly; a second call is a no-op
        /// rather than a duplicate registration.
        @discardableResult
        func start() -> Bool {
            guard !isRunning else { return true }

            let handler = onChange
            let deviceList: AudioObjectPropertyListenerBlock = { _, _ in
                Task { @MainActor in handler(.deviceListChanged) }
            }
            let defaultInput: AudioObjectPropertyListenerBlock = { _, _ in
                Task { @MainActor in handler(.defaultInputChanged) }
            }

            var listAddress = Self.deviceListAddress
            var defaultAddress = Self.defaultInputAddress

            let listStatus = AudioObjectAddPropertyListenerBlock(
                Self.systemObject, &listAddress, nil, deviceList
            )
            let defaultStatus = AudioObjectAddPropertyListenerBlock(
                Self.systemObject, &defaultAddress, nil, defaultInput
            )

            // Fail closed. If either registration failed, unwind the one that
            // succeeded rather than running half-observed and reporting success.
            guard listStatus == noErr, defaultStatus == noErr else {
                if listStatus == noErr {
                    AudioObjectRemovePropertyListenerBlock(
                        Self.systemObject, &listAddress, nil, deviceList
                    )
                }
                if defaultStatus == noErr {
                    AudioObjectRemovePropertyListenerBlock(
                        Self.systemObject, &defaultAddress, nil, defaultInput
                    )
                }
                return false
            }

            deviceListBlock = deviceList
            defaultInputBlock = defaultInput
            isRunning = true
            return true
        }

        /// Unregister both listeners. Safe to call when not running.
        func stop() {
            removeListeners()
            isRunning = false
        }

        private func removeListeners() {
            var listAddress = Self.deviceListAddress
            var defaultAddress = Self.defaultInputAddress

            if let deviceListBlock {
                AudioObjectRemovePropertyListenerBlock(
                    Self.systemObject, &listAddress, nil, deviceListBlock
                )
            }
            if let defaultInputBlock {
                AudioObjectRemovePropertyListenerBlock(
                    Self.systemObject, &defaultAddress, nil, defaultInputBlock
                )
            }

            deviceListBlock = nil
            defaultInputBlock = nil
        }
    }
#endif
