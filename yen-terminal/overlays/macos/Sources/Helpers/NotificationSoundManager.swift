#if os(macOS)
import AppKit
import AVFoundation
import Foundation

struct NotificationSoundOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

#if DEBUG
struct NotificationSoundPreferenceMutationCounts: Equatable, Sendable {
    var soundSelectionWrites: Int = 0
    var deliveryModeWrites: Int = 0
    var volumeWrites: Int = 0
    var soundWhenFocusedWrites: Int = 0
    var bannerWhenFocusedWrites: Int = 0

    static let zero = NotificationSoundPreferenceMutationCounts()
}
#endif

enum NotificationDeliveryMode: String, CaseIterable, Identifiable, Sendable {
    case bannerAndSound = "banner_sound"
    case bannerOnly = "banner_only"
    case soundOnly = "sound_only"
    case off = "off"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bannerAndSound: return "Banner + Sound"
        case .bannerOnly: return "Banner Only"
        case .soundOnly: return "Sound Only"
        case .off: return "Off"
        }
    }

    var allowsSound: Bool {
        self == .bannerAndSound || self == .soundOnly
    }

    var allowsSoundSelection: Bool {
        self != .off
    }
}

/// Which YEN notification stream a sound preference belongs to.
enum NotificationService: String, CaseIterable, Identifiable {
    case general = "General"
    case build = "Build"
    case usage = "Usage"

    var id: String { rawValue }

    static let configurableCases: [NotificationService] = [
        .general,
        .build,
        .usage,
    ]

    private var defaultsSuffix: String {
        switch self {
        case .general: return "General"
        case .build: return "Build"
        case .usage: return "Usage"
        }
    }

    /// The sound a stream plays before the user picks one. Plan limit alerts
    /// start with JP the Cat; the other streams start silent.
    var defaultSelectionID: String {
        self == .usage ? NotificationSoundManager.jpTheCatSelectionID : NotificationSoundManager.silentSelectionID
    }

    /// UserDefaults key for the sound selection preference.
    var defaultsKey: String { "YENNotificationSound\(defaultsSuffix)" }

    /// UserDefaults key for the per-service volume preference.
    var volumeDefaultsKey: String { "YENNotificationVolume\(defaultsSuffix)" }

    /// UserDefaults key for per-service delivery mode preference.
    var deliveryDefaultsKey: String { "YENNotificationDelivery\(defaultsSuffix)" }
}

/// Manages notification sound preferences and playback.
///
/// Stored sound selections are stable IDs:
///   - `none`
///   - `system:<encodedName>`
///   - `yen:jp-the-cat`, the one sound YEN ships (`JPTheCat` data asset)
///
/// Retired `custom:` and `bundled:` selections are accepted only as legacy input
/// and are normalized to `none` before playback or Settings snapshots read them.
@MainActor
final class NotificationSoundManager: NSObject, AVAudioPlayerDelegate {
    static let shared = NotificationSoundManager()
    static let silentSelectionID = "none"
    nonisolated static let jpTheCatSelectionID = "yen:jp-the-cat"
    nonisolated static let jpTheCatAssetName = "JPTheCat"
    /// Sounds YEN ships, listed before the system sounds in every pop-up.
    nonisolated static let builtInSounds = [NotificationSoundOption(id: jpTheCatSelectionID, name: "JP the Cat")]

    private static let audioExtensionPriority: [String] = ["m4a", "aiff", "aif", "wav", "mp3", "caf"]
    private static let audioExtensions: Set<String> = Set(audioExtensionPriority)
    private static let storageComponentAllowedCharacters: CharacterSet = {
        CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
    }()

    /// Cached list of system sounds.
    private(set) var systemSounds: [NotificationSoundOption] = []

    // MARK: - Focus Behavior Preferences

    nonisolated static let soundWhenFocusedKey = "YENNotificationSoundWhenFocused"
    nonisolated static let bannerWhenFocusedKey = "YENNotificationBannerWhenFocused"

    var soundWhenFocused: Bool {
        get { (UserDefaults.standard.object(forKey: Self.soundWhenFocusedKey) as? Bool) ?? true }
        set {
#if DEBUG
            testPreferenceMutationCounts.soundWhenFocusedWrites += 1
#endif
            UserDefaults.standard.set(newValue, forKey: Self.soundWhenFocusedKey)
        }
    }

    var bannerWhenFocused: Bool {
        get { (UserDefaults.standard.object(forKey: Self.bannerWhenFocusedKey) as? Bool) ?? false }
        set {
#if DEBUG
            testPreferenceMutationCounts.bannerWhenFocusedWrites += 1
#endif
            UserDefaults.standard.set(newValue, forKey: Self.bannerWhenFocusedKey)
        }
    }

    /// Currently playing sounds per service, to avoid overlapping repeats.
    private var activeSounds: [NotificationService: AVAudioPlayer] = [:]

    /// Sound currently playing as a preview in Settings.
    private var previewSound: AVAudioPlayer?

    /// Whether a preview sound is currently playing.
    private(set) var isPreviewPlaying: Bool = false

    private let fileManager = FileManager.default

    private enum SoundSelection: Equatable {
        case none
        case system(name: String)
        case builtIn(name: String)
        case custom(name: String)
        case bundled(pack: String, name: String)
    }

    private enum ResolvedSoundFileURL {
        case found(URL)
        case missing
    }

    private var resolvedFileURLCache: [String: ResolvedSoundFileURL] = [:]

#if DEBUG
    private var testPreferenceMutationCounts: NotificationSoundPreferenceMutationCounts = .zero
    private var testSoundFileURLResolutionSearchCount = 0
#endif

    private override init() {
        super.init()
        migrateGlobalVolume()
        refreshSystemSounds()
        migrateExpandedServiceDefaults()
        migrateLegacySelectionIdentifiersIfNeeded()
        migrateRetiredCustomSoundSelectionsIfNeeded()
    }

    /// One-time migration: copy the old global volume key to per-service keys, then remove it.
    private func migrateGlobalVolume() {
        let oldKey = "YENNotificationVolume"
        guard let oldValue = UserDefaults.standard.object(forKey: oldKey) as? Double else { return }
        for service in NotificationService.configurableCases {
            if UserDefaults.standard.object(forKey: service.volumeDefaultsKey) == nil {
                UserDefaults.standard.set(oldValue, forKey: service.volumeDefaultsKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: oldKey)
    }

    /// Seed newly added service keys from existing user prefs so upgrades are non-breaking.
    private func migrateExpandedServiceDefaults() {
        let defaults = UserDefaults.standard

        func seed(from source: NotificationService, into target: NotificationService) {
            if defaults.object(forKey: target.defaultsKey) == nil,
               let sound = defaults.string(forKey: source.defaultsKey)
            {
                defaults.set(sound, forKey: target.defaultsKey)
            }
            if defaults.object(forKey: target.volumeDefaultsKey) == nil,
               let volume = defaults.object(forKey: source.volumeDefaultsKey) as? Double
            {
                defaults.set(volume, forKey: target.volumeDefaultsKey)
            }
            if defaults.object(forKey: target.deliveryDefaultsKey) == nil,
               let modeRaw = defaults.string(forKey: source.deliveryDefaultsKey),
               let mode = NotificationDeliveryMode(rawValue: modeRaw)
            {
                defaults.set(mode.rawValue, forKey: target.deliveryDefaultsKey)
            }
        }

        seed(from: .general, into: .build)
    }

    // MARK: - Sound Discovery

    private static func uniqueSoundNames(from files: [String]) -> [String] {
        var names = Set<String>()
        for file in files {
            let ext = (file as NSString).pathExtension.lowercased()
            guard audioExtensions.contains(ext) else { continue }
            let baseName = (file as NSString).deletingPathExtension
            guard !baseName.hasPrefix(".") else { continue }
            names.insert(baseName)
        }
        return names.sorted()
    }

    private static func encodeStorageComponent(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: storageComponentAllowedCharacters) ?? component
    }

    private static func decodeStorageComponent(_ component: String) -> String? {
        component.removingPercentEncoding
    }

    private static func storedValue(for selection: SoundSelection) -> String {
        switch selection {
        case .none:
            return "none"
        case .system(let name):
            return "system:\(encodeStorageComponent(name))"
        case .builtIn(let name):
            return "yen:\(encodeStorageComponent(name))"
        case .custom(let name):
            return "custom:\(encodeStorageComponent(name))"
        case .bundled(let pack, let name):
            return "bundled:\(encodeStorageComponent(pack)):\(encodeStorageComponent(name))"
        }
    }

    private static func parseStoredValue(_ value: String) -> SoundSelection? {
        if value == "none" {
            return SoundSelection.none
        }

        let parts = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let prefix = parts.first else { return nil }
        switch prefix {
        case "system":
            guard parts.count == 2, let name = decodeStorageComponent(parts[1]) else { return nil }
            return .system(name: name)
        case "yen":
            guard parts.count == 2, let name = decodeStorageComponent(parts[1]),
                  builtInSounds.contains(where: { $0.id == "yen:\(name)" }) else { return nil }
            return .builtIn(name: name)
        case "custom":
            guard parts.count == 2, let name = decodeStorageComponent(parts[1]) else { return nil }
            return .custom(name: name)
        case "bundled":
            guard parts.count == 3,
                  let pack = decodeStorageComponent(parts[1]),
                  let name = decodeStorageComponent(parts[2]) else { return nil }
            return .bundled(pack: pack, name: name)
        default:
            return nil
        }
    }

    private static func displayName(for selection: SoundSelection) -> String {
        switch selection {
        case .none:
            return "None"
        case .system(let name):
            return name
        case .builtIn(let name):
            return builtInSounds.first { $0.id == "yen:\(name)" }?.name ?? "None"
        case .custom, .bundled:
            return "None"
        }
    }

    private func optionForSystemSound(named name: String) -> NotificationSoundOption {
        NotificationSoundOption(id: Self.storedValue(for: .system(name: name)), name: name)
    }

    private func canonicalSoundSelectionID(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isRetiredCustomOrBundledSelectionID(trimmed) {
            return Self.silentSelectionID
        }
        guard !trimmed.isEmpty else { return Self.silentSelectionID }
        if trimmed == Self.silentSelectionID {
            return Self.silentSelectionID
        }
        if let parsed = Self.parseStoredValue(trimmed) {
            // A `system:<name>` ID only means something if that sound exists on THIS Mac;
            // an imported or upgraded-past selection otherwise plays silence while still
            // rendering its name. Reconcile HERE: this is the single choke point behind
            // soundName/setSoundName/displayName/resolveFileURL, and the import path never
            // reaches `migrateLegacySelectionIdentifiersIfNeeded`.
            if case .system = parsed,
               !systemSounds.isEmpty,
               !systemSounds.contains(where: { $0.id == trimmed }) {
                return Self.silentSelectionID
            }
            return trimmed
        }
        return Self.silentSelectionID
    }

    private static func isRetiredCustomOrBundledSelectionID(_ selectionID: String) -> Bool {
        if selectionID.hasPrefix("custom:") || selectionID.hasPrefix("bundled:") {
            return true
        }
        guard let parsed = parseStoredValue(selectionID) else { return false }
        switch parsed {
        case .custom, .bundled:
            return true
        case .none, .system, .builtIn:
            return false
        }
    }

    @discardableResult
    private func migrateRetiredCustomSoundSelectionsIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        var migratedAnySelection = false
        for service in NotificationService.configurableCases {
            guard let stored = defaults.string(forKey: service.defaultsKey),
                  Self.isRetiredCustomOrBundledSelectionID(stored),
                  stored != Self.silentSelectionID else {
                continue
            }
            defaults.set(Self.silentSelectionID, forKey: service.defaultsKey)
            migratedAnySelection = true
        }
        return migratedAnySelection
    }

#if DEBUG
    static func _testBundledSelectionID(pack: String, name: String) -> String {
        storedValue(for: .bundled(pack: pack, name: name))
    }
#endif

    private func migrateLegacySelectionIdentifiersIfNeeded() {
        let defaults = UserDefaults.standard
        for service in NotificationService.configurableCases {
            guard let stored = defaults.string(forKey: service.defaultsKey) else { continue }
            let migrated: String
            if Self.isRetiredCustomOrBundledSelectionID(stored) {
                migrated = Self.silentSelectionID
            } else if stored == Self.silentSelectionID || Self.parseStoredValue(stored) != nil {
                migrated = stored
            } else if systemSounds.contains(where: { $0.name == stored }) {
                migrated = Self.storedValue(for: .system(name: stored))
            } else {
                migrated = Self.silentSelectionID
            }
            if migrated != stored {
                defaults.set(migrated, forKey: service.defaultsKey)
            }
        }
    }

    func refreshSystemSounds() {
        let systemSoundsPath = "/System/Library/Sounds"
        resolvedFileURLCache.removeAll()
        guard let files = try? fileManager.contentsOfDirectory(atPath: systemSoundsPath) else {
            print("NotificationSoundManager: system sounds not found at \(systemSoundsPath)")
            systemSounds = []
            return
        }

        let names = Self.uniqueSoundNames(from: files)
        systemSounds = names.map(optionForSystemSound)
        migrateLegacySelectionIdentifiersIfNeeded()
        migrateRetiredCustomSoundSelectionsIfNeeded()
    }

    // MARK: - Sound Selection Access

    /// Read the stored sound selection ID for a service. Returns `none` if unset.
    func soundName(for service: NotificationService) -> String {
        guard let raw = UserDefaults.standard.string(forKey: service.defaultsKey) else {
            return service.defaultSelectionID
        }
        let canonical = canonicalSoundSelectionID(raw)
        if canonical != raw {
            UserDefaults.standard.set(canonical, forKey: service.defaultsKey)
        }
        return canonical
    }

    /// Write the stored sound selection ID for a service.
    func setSoundName(_ selectionID: String, for service: NotificationService) {
#if DEBUG
        testPreferenceMutationCounts.soundSelectionWrites += 1
#endif
        UserDefaults.standard.set(canonicalSoundSelectionID(selectionID), forKey: service.defaultsKey)
    }

    static func isValidStoredSelectionID(_ selectionID: String) -> Bool {
        let trimmed = selectionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed == Self.silentSelectionID
            || isRetiredCustomOrBundledSelectionID(trimmed)
            || parseStoredValue(trimmed) != nil
    }

    /// Human-readable display name for a stored sound selection ID.
    func displayName(for selectionID: String) -> String {
        let canonicalID = canonicalSoundSelectionID(selectionID)
        if canonicalID == Self.silentSelectionID {
            return "None"
        }
        if let parsed = Self.parseStoredValue(canonicalID) {
            return Self.displayName(for: parsed)
        }
        return "None"
    }

    /// Read the per-service volume (0.0 - 1.0). Returns 1.0 if unset. Clamped on read.
    func volume(for service: NotificationService) -> Double {
        let val = UserDefaults.standard.object(forKey: service.volumeDefaultsKey)
        let raw = (val as? Double) ?? 1.0
        return min(max(raw, 0.0), 1.0)
    }

    /// Write the per-service volume (0.0 - 1.0) to UserDefaults.
    func setVolume(_ volume: Double, for service: NotificationService) {
#if DEBUG
        testPreferenceMutationCounts.volumeWrites += 1
#endif
        UserDefaults.standard.set(min(max(volume, 0.0), 1.0), forKey: service.volumeDefaultsKey)
    }

    /// Read per-service delivery mode. Defaults to banner + sound.
    func deliveryMode(for service: NotificationService) -> NotificationDeliveryMode {
        let raw = UserDefaults.standard.string(forKey: service.deliveryDefaultsKey)
            ?? NotificationDeliveryMode.bannerAndSound.rawValue
        return NotificationDeliveryMode(rawValue: raw) ?? .bannerAndSound
    }

    /// Write per-service delivery mode.
    func setDeliveryMode(_ mode: NotificationDeliveryMode, for service: NotificationService) {
#if DEBUG
        testPreferenceMutationCounts.deliveryModeWrites += 1
#endif
        UserDefaults.standard.set(mode.rawValue, forKey: service.deliveryDefaultsKey)
    }

    // MARK: - Notification Sound Resolution

    /// Resolve the user's sound preference for a service and play it via AVAudioPlayer.
    /// Returns `true` when playback started, `false` when the selection resolves to silence.
    func resolveAndPlay(for service: NotificationService) -> Bool {
        let selectionID = soundName(for: service)
        let vol = volume(for: service)

        if selectionID == Self.silentSelectionID || vol == 0.0 {
            return false
        }

        guard let player = makePlayer(for: selectionID) else {
            return false
        }

        activeSounds = activeSounds.filter { $0.value.isPlaying }

        if let active = activeSounds[service], active.isPlaying {
            active.stop()
            active.delegate = nil
            activeSounds.removeValue(forKey: service)
        }

        player.delegate = self
        player.volume = Float(vol)
        player.prepareToPlay()
        player.play()
        activeSounds[service] = player

        return true
    }

    // MARK: - Preview Playback (Settings)

    /// Play a sound for preview in Settings. Stops any current preview first.
    func playPreview(soundName selectionID: String, volume: Double) {
        stopPreview()

        if selectionID == Self.silentSelectionID { return }

        guard let player = makePlayer(for: selectionID) else { return }
        player.delegate = self
        player.volume = Float(min(max(volume, 0.0), 1.0))
        player.prepareToPlay()
        player.play()
        previewSound = player
        isPreviewPlaying = true
    }

    /// Stop the current preview sound.
    func stopPreview() {
        previewSound?.stop()
        previewSound = nil
        isPreviewPlaying = false
    }

    // MARK: - AVAudioPlayerDelegate

    private func clearPlaybackReferences(for player: AVAudioPlayer) {
        activeSounds = activeSounds.filter { $0.value !== player }
        if previewSound === player {
            previewSound = nil
            isPreviewPlaying = false
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.clearPlaybackReferences(for: player)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor in
            self.clearPlaybackReferences(for: player)
        }
    }

#if DEBUG
    // Test hooks for playback lifecycle assertions.
    func _testInjectActiveSound(_ player: AVAudioPlayer, for service: NotificationService) {
        activeSounds[service] = player
    }

    func _testActiveSound(for service: NotificationService) -> AVAudioPlayer? {
        activeSounds[service]
    }

    func _testInjectPreviewSound(_ player: AVAudioPlayer?) {
        previewSound = player
        isPreviewPlaying = (player != nil)
    }

    func _testPreviewSound() -> AVAudioPlayer? {
        previewSound
    }

    func _testResetPlaybackState() {
        activeSounds.removeAll()
        previewSound = nil
        isPreviewPlaying = false
    }

    func _testResetSoundFileURLResolutionCache() {
        resolvedFileURLCache.removeAll()
        testSoundFileURLResolutionSearchCount = 0
    }

    var _testSoundFileURLResolutionSearchCount: Int {
        testSoundFileURLResolutionSearchCount
    }

    func _testResetPreferenceMutationCounts() {
        testPreferenceMutationCounts = .zero
    }

    var _testPreferenceMutationCounts: NotificationSoundPreferenceMutationCounts {
        testPreferenceMutationCounts
    }
#endif

    // MARK: - File Resolution

    /// A player for a stored selection: a built-in sound from the asset catalog, a system sound from its file.
    private func makePlayer(for selectionID: String) -> AVAudioPlayer? {
        let canonicalID = canonicalSoundSelectionID(selectionID)
        if canonicalID == Self.jpTheCatSelectionID {
            guard let asset = NSDataAsset(name: Self.jpTheCatAssetName) else { return nil }
            return try? AVAudioPlayer(data: asset.data)
        }
        guard let url = resolveFileURL(for: canonicalID) else { return nil }
        return try? AVAudioPlayer(contentsOf: url)
    }

    private func resolveFileURL(for selectionID: String) -> URL? {
        let canonicalID = canonicalSoundSelectionID(selectionID)
        if let cached = resolvedFileURLCache[canonicalID] {
            switch cached {
            case .found(let url):
                return url
            case .missing:
                return nil
            }
        }

        guard let selection = Self.parseStoredValue(canonicalID) else {
            return nil
        }

        switch selection {
        case .none, .builtIn, .custom, .bundled:
            return nil
        case .system(let name):
            let url = findSoundFile(named: name, in: "/System/Library/Sounds")
            if let url {
                resolvedFileURLCache[canonicalID] = .found(url)
            } else {
                resolvedFileURLCache[canonicalID] = .missing
            }
            return url
        }
    }

    /// Find a sound file by name (without extension) in a directory.
    private func findSoundFile(named name: String, in directory: String) -> URL? {
#if DEBUG
        testSoundFileURLResolutionSearchCount += 1
#endif
        for ext in Self.audioExtensionPriority {
            let path = "\(directory)/\(name).\(ext)"
            if fileManager.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
#endif // os(macOS)
