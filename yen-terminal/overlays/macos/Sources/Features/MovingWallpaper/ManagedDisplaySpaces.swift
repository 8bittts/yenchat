import AppKit

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_: CGSConnectionID) -> Unmanaged<CFArray>?

/// Snapshot of the active and ordered Spaces for each connected display.
struct ManagedDisplaySpacesSnapshot: Equatable {
    let activeSpaceByDisplayID: [CGDirectDisplayID: UInt64]
    /// Each display's Spaces in the order the system lists them (Mission
    /// Control order), for the displays the system actually listed. A display
    /// that fell back to the global Space has no entry here.
    let orderedSpacesByDisplayID: [CGDirectDisplayID: [UInt64]]

    static func current(screens: [NSScreen] = NSScreen.screens) -> ManagedDisplaySpacesSnapshot {
        let rawEntries = (CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]]) ?? []
        return from(
            rawEntries: rawEntries,
            screensByDisplayIdentifier: displayIdentifiers(for: screens),
            fallbackGlobalSpaceID: activeGlobalSpaceID()
        )
    }

    /// The active Space of the display with keyboard focus. The fallback for a
    /// display the managed-spaces snapshot does not list.
    static func activeGlobalSpaceID() -> UInt64 {
        UInt64(CGSSpace.active().rawValue)
    }

    static func from(
        rawEntries: [[String: Any]],
        screensByDisplayIdentifier: [String: CGDirectDisplayID],
        fallbackGlobalSpaceID: UInt64
    ) -> ManagedDisplaySpacesSnapshot {
        // Collapse (never trap) if two identifiers resolve to the same displayID.
        var activeSpaceByDisplayID = Dictionary(
            screensByDisplayIdentifier.values.map { ($0, fallbackGlobalSpaceID) },
            uniquingKeysWith: { first, _ in first }
        )
        var orderedSpacesByDisplayID: [CGDirectDisplayID: [UInt64]] = [:]

        for entry in rawEntries {
            guard
                let displayIdentifier = entry["Display Identifier"] as? String,
                let displayID = screensByDisplayIdentifier[displayIdentifier],
                let currentSpace = spaceID(from: entry["Current Space"])
            else {
                continue
            }

            activeSpaceByDisplayID[displayID] = currentSpace

            if let spaces = entry["Spaces"] as? [Any] {
                let ordered = spaces.compactMap(spaceID(from:))
                if !ordered.isEmpty {
                    orderedSpacesByDisplayID[displayID] = ordered
                }
            }
        }

        return ManagedDisplaySpacesSnapshot(
            activeSpaceByDisplayID: activeSpaceByDisplayID,
            orderedSpacesByDisplayID: orderedSpacesByDisplayID
        )
    }

    private static func displayIdentifiers(for screens: [NSScreen]) -> [String: CGDirectDisplayID] {
        Dictionary(
            screens.compactMap { screen -> (String, CGDirectDisplayID)? in
                guard
                    let displayID = screen.displayID,
                    let identifier = DisplayIdentity.systemUUID(for: displayID)
                else {
                    return nil
                }
                return (identifier, displayID)
            },
            // Two screens reporting the same display UUID would otherwise trap.
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func spaceID(from value: Any?) -> UInt64? {
        // Every numeric plist value bridges to NSNumber, whatever its width.
        ((value as? [String: Any])?["id64"] as? NSNumber)?.uint64Value
    }
}
