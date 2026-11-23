import Foundation

/// Preferences kept in memory. A named suite leaves an empty file in
/// `~/Library/Preferences` even after `removePersistentDomain`.
final class WallpaperMemoryDefaults: UserDefaults {
    private nonisolated(unsafe) var values: [String: Any] = [:]

    init() {
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { values[defaultName] = nil }
}
