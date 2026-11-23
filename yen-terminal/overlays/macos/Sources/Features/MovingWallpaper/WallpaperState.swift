import CoreGraphics
import CoreMedia
import Foundation

/// A single per-desktop wallpaper assignment. The optional `youtubeOrigin` is
/// retained so persistence can re-download a missing local file on next launch.
struct WallpaperEntry: Equatable {
    var localURL: URL
    var youtubeOrigin: String?
}

/// All in-memory wallpaper state. Replaces the previous parallel dictionaries
/// (`desktopFiles`, `youtubeURLs`, `playbackPositions`, `knownSpaces`) so that
/// every mutation touches one canonical store.
struct WallpaperState: Equatable {
    var entries: [DesktopKey: WallpaperEntry] = [:]
    var playbackPositions: [DesktopKey: CMTime] = [:]
    /// Every Space we've ever observed on each display. macOS exposes no API to
    /// enumerate Spaces, so we accumulate them as the user visits.
    var knownSpaces: [CGDirectDisplayID: Set<UInt64>] = [:]
    /// Each Per Desktop assignment's position among its display's Spaces, in
    /// the system's order, the last time that display listed the Space. Saved,
    /// because it is what finds the desktop again once the ids change.
    var spacePositions: [DesktopKey: Int] = [:]

    var isEmpty: Bool { entries.isEmpty }

    func localURL(for key: DesktopKey) -> URL? { entries[key]?.localURL }

    /// The entry with the smallest `DesktopKey`, chosen deterministically so that
    /// collapsing differing per-desktop assignments to one shared wallpaper always
    /// picks the same one (dictionary order is otherwise arbitrary). In
    /// `.allDesktops` mode every entry is identical, so this is stable there too.
    var canonicalEntry: WallpaperEntry? {
        entries.min {
            ($0.key.displayID, $0.key.spaceID) < ($1.key.displayID, $1.key.spaceID)
        }?.value
    }

    /// The single shared URL when all desktops share one wallpaper, or `nil`.
    var sharedLocalURL: URL? { canonicalEntry?.localURL }

    /// Write one assignment. A saved playback position belongs to the file that
    /// was playing, so it is dropped when the key gets a different file;
    /// otherwise a new video would start at the old one's offset.
    private mutating func store(_ entry: WallpaperEntry, at key: DesktopKey) {
        if entries[key]?.localURL != entry.localURL {
            playbackPositions.removeValue(forKey: key)
        }
        entries[key] = entry
    }

    mutating func setEntry(_ entry: WallpaperEntry, for key: DesktopKey) {
        store(entry, at: key)
        // Recording the all-desktops sentinel would surface a phantom "Desktop 1"
        // row in the Per Desktop menu after an all-desktops restore-redownload.
        if !key.isAllDesktops {
            knownSpaces[key.displayID, default: []].insert(key.spaceID)
        }
    }

    mutating func clearEntry(for key: DesktopKey) {
        entries.removeValue(forKey: key)
        playbackPositions.removeValue(forKey: key)
        spacePositions.removeValue(forKey: key)
    }

    /// Replace all assignments with a single shared entry across the given displays.
    /// Used when switching to `.allDesktops` mode or when the wallpaper changes globally.
    mutating func applyShared(entry: WallpaperEntry, across displayIDs: [CGDirectDisplayID]) {
        let keys = Set(displayIDs.map(DesktopKey.init(displayID:)))
        for key in Array(entries.keys) where !keys.contains(key) {
            entries.removeValue(forKey: key)
        }
        playbackPositions = playbackPositions.filter { keys.contains($0.key) }
        for key in keys {
            store(entry, at: key)
        }
    }

    /// Apply one wallpaper choice according to the current mode.
    ///
    /// - allDesktops: pin the entry on every connected display (sentinel space 0).
    /// - perDesktop with a display: assign that display's given or current Space.
    /// - perDesktop with no display ("for all"): assign every connected display's current Space.
    @discardableResult
    mutating func assign(
        _ entry: WallpaperEntry,
        mode: WallpaperMode,
        displayID: CGDirectDisplayID?,
        spaceID: UInt64?,
        connectedDisplayIDs: [CGDirectDisplayID],
        currentSpaceID: (CGDirectDisplayID) -> UInt64
    ) -> [DesktopKey] {
        switch mode {
        case .allDesktops:
            applyShared(entry: entry, across: connectedDisplayIDs)
            return connectedDisplayIDs.map { DesktopKey(displayID: $0) }
        case .perDesktop:
            if let displayID {
                let space = spaceID ?? currentSpaceID(displayID)
                let key = DesktopKey(displayID: displayID, spaceID: space)
                setEntry(entry, for: key)
                return [key]
            }
            return connectedDisplayIDs.map { id in
                let key = DesktopKey(displayID: id, spaceID: currentSpaceID(id))
                setEntry(entry, for: key)
                return key
            }
        }
    }

    /// Replace this state's entries and playback positions with `persisted`'s,
    /// but keep every Space we already saw from the live system snapshot.
    /// Used after `refreshManagedDisplaySpaces()` so loading persistence does
    /// not erase Spaces the user can currently switch to — those would never
    /// appear in the Per Desktop menu otherwise.
    mutating func adopt(persisted: WallpaperState) {
        let liveKnownSpaces = knownSpaces
        self = persisted
        for (displayID, spaces) in liveKnownSpaces {
            knownSpaces[displayID, default: []].formUnion(spaces)
        }
    }

    /// Drop assignments for displays not in `connectedDisplayIDs` and pin the
    /// shared value (if any) to every connected display. With no display
    /// connected the state is left alone, so the wallpaper is still there for
    /// the next display.
    @discardableResult
    mutating func reconcileAllDesktops(connectedDisplayIDs: [CGDirectDisplayID]) -> Bool {
        guard let shared = canonicalEntry, !connectedDisplayIDs.isEmpty else { return false }
        let expected = Set(connectedDisplayIDs.map(DesktopKey.init(displayID:)))
        var changed = false

        for key in Array(entries.keys) where !expected.contains(key) {
            entries.removeValue(forKey: key)
            playbackPositions.removeValue(forKey: key)
            changed = true
        }

        for id in connectedDisplayIDs {
            let key = DesktopKey(displayID: id)
            if entries[key] != shared {
                store(shared, at: key)
                changed = true
            }
        }

        return changed
    }

    /// Re-key existing assignments to (display, currentSpace) so per-desktop
    /// switching from `.allDesktops` preserves the wallpaper on the active Space.
    mutating func migrateToPerDesktop(currentSpace: (CGDirectDisplayID) -> UInt64) {
        let snapshot = entries
        let positions = playbackPositions
        entries.removeAll()
        playbackPositions.removeAll()
        for (oldKey, entry) in snapshot {
            let space = currentSpace(oldKey.displayID)
            let newKey = DesktopKey(displayID: oldKey.displayID, spaceID: space)
            entries[newKey] = entry
            playbackPositions[newKey] = positions[oldKey]
            knownSpaces[oldKey.displayID, default: []].insert(space)
        }
    }
    /// Keep Per Desktop assignments on their desktops when macOS renumbers a
    /// display's Spaces, which it does when the display is plugged in again.
    ///
    /// `liveSpaces` holds each listed display's Spaces in the system's order.
    /// When none of a display's assigned Spaces is live any more, each of its
    /// assignments moves to the live Space at its saved position, and the
    /// first one with no usable position goes to the display's current Space
    /// (records from older builds carry no position). A live Space that
    /// already has a wallpaper is never overwritten, nothing moves to another
    /// display, and an assignment that finds no Space is kept for later. While
    /// any assigned Space is still live, a missing one was removed by the user
    /// and nothing moves. Returns whether anything to save changed.
    @discardableResult
    mutating func followSpaces(
        _ liveSpaces: [CGDirectDisplayID: [UInt64]],
        currentSpace: (CGDirectDisplayID) -> UInt64
    ) -> Bool {
        var changed = false
        for (displayID, live) in liveSpaces where !live.isEmpty {
            let assigned = entries.keys.filter { $0.displayID == displayID && !$0.isAllDesktops }
            if !assigned.isEmpty, !assigned.contains(where: { live.contains($0.spaceID) }) {
                changed = moveOrphans(assigned, onto: live, currentSpace: currentSpace(displayID)) || changed
            }
            for key in entries.keys where key.displayID == displayID && !key.isAllDesktops {
                guard let position = live.firstIndex(of: key.spaceID), spacePositions[key] != position else { continue }
                spacePositions[key] = position
                changed = true
            }
        }
        return changed
    }

    private mutating func moveOrphans(_ orphans: [DesktopKey], onto live: [UInt64], currentSpace: UInt64) -> Bool {
        var changed = false
        var unplaced: [DesktopKey] = []
        for key in orphans.sorted(by: { $0.spaceID < $1.spaceID }) {
            if let position = spacePositions[key], live.indices.contains(position),
               move(key, to: live[position]) {
                changed = true
            } else {
                unplaced.append(key)
            }
        }
        if let first = unplaced.first, live.contains(currentSpace), move(first, to: currentSpace) {
            changed = true
        }
        return changed
    }

    /// Move one assignment, with its playback position, to another Space of
    /// the same display. Refuses a Space that already has a wallpaper.
    private mutating func move(_ key: DesktopKey, to spaceID: UInt64) -> Bool {
        let target = DesktopKey(displayID: key.displayID, spaceID: spaceID)
        guard entries[target] == nil, let entry = entries.removeValue(forKey: key) else { return false }
        entries[target] = entry
        playbackPositions[target] = playbackPositions.removeValue(forKey: key)
        spacePositions.removeValue(forKey: key)
        knownSpaces[key.displayID, default: []].insert(spaceID)
        return true
    }
}
