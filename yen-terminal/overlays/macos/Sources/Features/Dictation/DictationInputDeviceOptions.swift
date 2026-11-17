#if os(macOS)
    import CoreAudio
    import Foundation

    /// One row in the Settings microphone picker.
    ///
    /// `identifier` is the persisted device UID, or `systemDefaultIdentifier` for the
    /// "System Default" row. That sentinel is the empty string so it round-trips
    /// through `DictationAudioDeviceStore`, which already treats empty as absent.
    struct DictationInputDeviceOption: Identifiable, Equatable, Sendable {
        static let systemDefaultIdentifier = ""

        let identifier: String
        let displayName: String
        /// True when this row is the saved choice but the device is not present.
        /// The row stays in the list so the user can see what they picked instead of
        /// silently watching the selection snap back to System Default.
        let isDisconnected: Bool

        var id: String { identifier }
        var isSystemDefault: Bool { identifier == Self.systemDefaultIdentifier }
    }

    enum DictationInputDeviceOptionsBuilder {
        /// Build the picker rows.
        ///
        /// Order is fixed: System Default first, then connected devices in HAL order,
        /// then the saved-but-missing device last if there is one.
        ///
        /// - Parameters:
        ///   - devices: input devices present right now.
        ///   - selectedUID: the saved preference, `nil` for System Default.
        ///   - defaultDeviceName: name the system default currently resolves to, used
        ///     to label the first row. `nil` leaves it unqualified.
        static func makeOptions(
            devices: [DictationAudioDevice],
            selectedUID: String?,
            defaultDeviceName: String?
        ) -> [DictationInputDeviceOption] {
            var options: [DictationInputDeviceOption] = [
                DictationInputDeviceOption(
                    identifier: DictationInputDeviceOption.systemDefaultIdentifier,
                    displayName: systemDefaultLabel(resolvingTo: defaultDeviceName),
                    isDisconnected: false
                ),
            ]

            options.append(contentsOf: devices.map { device in
                DictationInputDeviceOption(
                    identifier: device.uid,
                    displayName: device.name,
                    isDisconnected: false
                )
            })

            // A saved device that is not in `devices` still needs a row, otherwise the
            // picker would render the user's choice as System Default and repeat the
            // silent downgrade this feature exists to remove.
            if let selectedUID,
               !selectedUID.isEmpty,
               !devices.contains(where: { $0.uid == selectedUID }) {
                options.append(
                    DictationInputDeviceOption(
                        identifier: selectedUID,
                        displayName: "\(shortName(for: selectedUID)) (not connected)",
                        isDisconnected: true
                    )
                )
            }

            return options
        }

        /// The identifier the picker should show as selected.
        static func selectedIdentifier(for selectedUID: String?) -> String {
            guard let selectedUID, !selectedUID.isEmpty else {
                return DictationInputDeviceOption.systemDefaultIdentifier
            }
            return selectedUID
        }

        static func systemDefaultLabel(resolvingTo name: String?) -> String {
            guard let name, !name.isEmpty else { return "System Default" }
            return "System Default (\(name))"
        }

        /// Device UIDs are opaque and can be long, so show a trimmed form when the
        /// device is gone and no friendly name is available.
        private static func shortName(for uid: String) -> String {
            let trimmed = uid.split(separator: ":").first.map(String.init) ?? uid
            return trimmed.isEmpty ? uid : trimmed
        }
    }
#endif
