import AVFoundation
import Foundation
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct NotificationSoundImportTests {
    @Test func retiredCustomAndBundledSelectionsMigrateToNoneWithoutDeletingFiles() throws {
        let manager = NotificationSoundManager.shared
        let defaults = UserDefaults.standard
        let fileManager = FileManager.default
        let customDir = customSoundsDirectory(fileManager: fileManager)
        let appSupportRoot = customDir.deletingLastPathComponent()
        let packsRoot = appSupportRoot.appendingPathComponent("sound-packs", isDirectory: true)
        let packRoot = packsRoot.appendingPathComponent("Retired Pack \(UUID().uuidString)", isDirectory: true)
        let customName = "yen-retired-custom-\(UUID().uuidString)"
        let customFile = customDir.appendingPathComponent("\(customName).m4a")
        let bundledName = "Retired Tone"
        let bundledFile = packRoot.appendingPathComponent("\(bundledName).m4a")

        try fileManager.createDirectory(
            at: customDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.createDirectory(
            at: packRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Data("retired-custom".utf8).write(to: customFile)
        try Data("retired-bundled".utf8).write(to: bundledFile)

        defaults.set("custom:\(customName)", forKey: NotificationService.general.defaultsKey)
        defaults.set(
            NotificationSoundManager._testBundledSelectionID(pack: packRoot.lastPathComponent, name: bundledName),
            forKey: NotificationService.build.defaultsKey
        )
        defaults.set(NotificationDeliveryMode.soundOnly.rawValue, forKey: NotificationService.general.deliveryDefaultsKey)
        defaults.set(0.3, forKey: NotificationService.general.volumeDefaultsKey)
        defaults.set(false, forKey: NotificationSoundManager.soundWhenFocusedKey)
        defaults.set(true, forKey: NotificationSoundManager.bannerWhenFocusedKey)

        defer {
            defaults.removeObject(forKey: NotificationService.general.defaultsKey)
            defaults.removeObject(forKey: NotificationService.build.defaultsKey)
            defaults.removeObject(forKey: NotificationService.general.deliveryDefaultsKey)
            defaults.removeObject(forKey: NotificationService.general.volumeDefaultsKey)
            defaults.removeObject(forKey: NotificationSoundManager.soundWhenFocusedKey)
            defaults.removeObject(forKey: NotificationSoundManager.bannerWhenFocusedKey)
            try? fileManager.removeItem(at: customFile)
            try? fileManager.removeItem(at: packRoot)
        }

        #expect(manager.soundName(for: .general) == NotificationSoundManager.silentSelectionID)
        #expect(manager.soundName(for: .build) == NotificationSoundManager.silentSelectionID)
        #expect(defaults.string(forKey: NotificationService.general.defaultsKey) == NotificationSoundManager.silentSelectionID)
        #expect(defaults.string(forKey: NotificationService.build.defaultsKey) == NotificationSoundManager.silentSelectionID)
        #expect(fileManager.fileExists(atPath: customFile.path))
        #expect(fileManager.fileExists(atPath: bundledFile.path))
        #expect(!manager.resolveAndPlay(for: .general))
        #expect(!manager.resolveAndPlay(for: .build))
        #expect(manager.deliveryMode(for: .general) == .soundOnly)
        #expect(abs(manager.volume(for: .general) - 0.3) < 0.001)
        #expect(!manager.soundWhenFocused)
        #expect(manager.bannerWhenFocused)
    }

    @Test func malformedRetiredCustomAndBundledSelectionsMigrateToNone() {
        let manager = NotificationSoundManager.shared
        let defaults = UserDefaults.standard

        defer {
            defaults.removeObject(forKey: NotificationService.general.defaultsKey)
            defaults.removeObject(forKey: NotificationService.build.defaultsKey)
        }

        defaults.set("custom:", forKey: NotificationService.general.defaultsKey)
        defaults.set("bundled:MissingOnly", forKey: NotificationService.build.defaultsKey)

        #expect(manager.soundName(for: .general) == NotificationSoundManager.silentSelectionID)
        #expect(manager.soundName(for: .build) == NotificationSoundManager.silentSelectionID)
        #expect(defaults.string(forKey: NotificationService.general.defaultsKey) == NotificationSoundManager.silentSelectionID)
        #expect(defaults.string(forKey: NotificationService.build.defaultsKey) == NotificationSoundManager.silentSelectionID)
    }

    @Test func soundNameReadCanonicalizesOnlyRequestedService() {
        let manager = NotificationSoundManager.shared
        let defaults = UserDefaults.standard
        let generalKey = NotificationService.general.defaultsKey
        let buildKey = NotificationService.build.defaultsKey
        let originalGeneral = defaults.object(forKey: generalKey)
        let originalBuild = defaults.object(forKey: buildKey)
        let retiredGeneral = "custom:general-retired-\(UUID().uuidString)"
        let retiredBuild = "custom:build-retired-\(UUID().uuidString)"

        defer {
            if let originalGeneral {
                defaults.set(originalGeneral, forKey: generalKey)
            } else {
                defaults.removeObject(forKey: generalKey)
            }
            if let originalBuild {
                defaults.set(originalBuild, forKey: buildKey)
            } else {
                defaults.removeObject(forKey: buildKey)
            }
        }

        defaults.set(retiredGeneral, forKey: generalKey)
        defaults.set(retiredBuild, forKey: buildKey)

        #expect(manager.soundName(for: .general) == NotificationSoundManager.silentSelectionID)
        #expect(defaults.string(forKey: generalKey) == NotificationSoundManager.silentSelectionID)
        #expect(defaults.string(forKey: buildKey) == retiredBuild)

        #expect(manager.soundName(for: .build) == NotificationSoundManager.silentSelectionID)
        #expect(defaults.string(forKey: buildKey) == NotificationSoundManager.silentSelectionID)
    }

    @Test func soundNameCanonicalizesAndPersistsRawSelectionsOnRead() {
        let manager = NotificationSoundManager.shared
        let defaults = UserDefaults.standard
        let generalKey = NotificationService.general.defaultsKey
        let buildKey = NotificationService.build.defaultsKey
        let originalGeneral = defaults.object(forKey: generalKey)
        let originalBuild = defaults.object(forKey: buildKey)

        defer {
            if let originalGeneral {
                defaults.set(originalGeneral, forKey: generalKey)
            } else {
                defaults.removeObject(forKey: generalKey)
            }
            if let originalBuild {
                defaults.set(originalBuild, forKey: buildKey)
            } else {
                defaults.removeObject(forKey: buildKey)
            }
        }

        defaults.set("  system:Glass\n", forKey: generalKey)
        defaults.set("unknown-selection-shape", forKey: buildKey)

        #expect(manager.soundName(for: .general) == "system:Glass")
        #expect(manager.soundName(for: .build) == NotificationSoundManager.silentSelectionID)
        #expect(defaults.string(forKey: generalKey) == "system:Glass")
        #expect(defaults.string(forKey: buildKey) == NotificationSoundManager.silentSelectionID)
    }

    @Test func validationAcceptsRetiredSelectionsButStillRejectsUnknownShapes() {
        let bundledID = NotificationSoundManager._testBundledSelectionID(pack: "Warcraft III", name: "Ready")

        #expect(NotificationSoundManager.isValidStoredSelectionID("custom:Build%20Done"))
        #expect(NotificationSoundManager.isValidStoredSelectionID("custom:"))
        #expect(NotificationSoundManager.isValidStoredSelectionID(bundledID))
        #expect(NotificationSoundManager.isValidStoredSelectionID("bundled:MissingOnly"))
        #expect(NotificationSoundManager.isValidStoredSelectionID("none"))
        #expect(NotificationSoundManager.isValidStoredSelectionID("system:Glass"))
        #expect(!NotificationSoundManager.isValidStoredSelectionID(""))
        #expect(!NotificationSoundManager.isValidStoredSelectionID("invalid-selection"))
    }

    @Test func retiredPreviewSelectionDoesNotPlay() {
        let manager = NotificationSoundManager.shared
        manager._testResetPlaybackState()
        defer { manager._testResetPlaybackState() }

        manager.playPreview(soundName: "custom:retired-tone", volume: 1.0)
        #expect(!manager.isPreviewPlaying)

        manager.playPreview(
            soundName: NotificationSoundManager._testBundledSelectionID(pack: "Retired", name: "Tone"),
            volume: 1.0
        )
        #expect(!manager.isPreviewPlaying)
    }

    @Test func playbackLifecycleFinishCleansOnlyMatchedReferences() async throws {
        let manager = NotificationSoundManager.shared
        let source = try firstSystemSoundURL(fileManager: .default)
        let buildPlayer = try AVAudioPlayer(contentsOf: source)
        let generalPlayer = try AVAudioPlayer(contentsOf: source)
        manager._testResetPlaybackState()
        defer { manager._testResetPlaybackState() }

        manager._testInjectActiveSound(buildPlayer, for: .build)
        manager._testInjectActiveSound(generalPlayer, for: .general)
        manager._testInjectPreviewSound(buildPlayer)

        manager.audioPlayerDidFinishPlaying(buildPlayer, successfully: true)
        await settlePlaybackDelegateCallbacks()

        #expect(manager._testActiveSound(for: .build) == nil)
        #expect(manager._testActiveSound(for: .general) === generalPlayer)
        #expect(manager._testPreviewSound() == nil)
        #expect(!manager.isPreviewPlaying)
    }

    @Test func playbackLifecycleDecodeErrorCleansOnlyMatchedReferences() async throws {
        let manager = NotificationSoundManager.shared
        let source = try firstSystemSoundURL(fileManager: .default)
        let buildPlayer = try AVAudioPlayer(contentsOf: source)
        let untouchedPlayer = try AVAudioPlayer(contentsOf: source)
        manager._testResetPlaybackState()
        defer { manager._testResetPlaybackState() }

        manager._testInjectActiveSound(buildPlayer, for: .build)
        manager._testInjectActiveSound(untouchedPlayer, for: .general)
        manager._testInjectPreviewSound(buildPlayer)

        manager.audioPlayerDecodeErrorDidOccur(buildPlayer, error: NotificationSoundImportTestError.syntheticDecodeFailure)
        await settlePlaybackDelegateCallbacks()

        #expect(manager._testActiveSound(for: .build) == nil)
        #expect(manager._testActiveSound(for: .general) === untouchedPlayer)
        #expect(manager._testPreviewSound() == nil)
        #expect(!manager.isPreviewPlaying)
    }

    @Test func playbackLifecycleFinishKeepsNewerReplayForSameService() async throws {
        let manager = NotificationSoundManager.shared
        let source = try firstSystemSoundURL(fileManager: .default)
        let oldPlayer = try AVAudioPlayer(contentsOf: source)
        let replayPlayer = try AVAudioPlayer(contentsOf: source)
        manager._testResetPlaybackState()
        defer { manager._testResetPlaybackState() }

        manager._testInjectActiveSound(oldPlayer, for: .general)
        manager._testInjectActiveSound(replayPlayer, for: .general)
        manager._testInjectPreviewSound(replayPlayer)

        manager.audioPlayerDidFinishPlaying(oldPlayer, successfully: true)
        await settlePlaybackDelegateCallbacks()

        #expect(manager._testActiveSound(for: .general) === replayPlayer)
        #expect(manager._testPreviewSound() === replayPlayer)
        #expect(manager.isPreviewPlaying)
    }

    @Test func playbackLifecycleDecodeErrorIgnoresUntrackedPlayer() async throws {
        let manager = NotificationSoundManager.shared
        let source = try firstSystemSoundURL(fileManager: .default)
        let trackedPlayer = try AVAudioPlayer(contentsOf: source)
        let untrackedPlayer = try AVAudioPlayer(contentsOf: source)
        manager._testResetPlaybackState()
        defer { manager._testResetPlaybackState() }

        manager._testInjectActiveSound(trackedPlayer, for: .general)
        manager._testInjectPreviewSound(trackedPlayer)

        manager.audioPlayerDecodeErrorDidOccur(untrackedPlayer, error: nil)
        await settlePlaybackDelegateCallbacks()

        #expect(manager._testActiveSound(for: .general) === trackedPlayer)
        #expect(manager._testPreviewSound() === trackedPlayer)
        #expect(manager.isPreviewPlaying)
    }

    @Test func repeatedSystemPlaybackCachesURLResolutionWithoutReusingPlayers() throws {
        let manager = NotificationSoundManager.shared
        let selectionID = try firstSystemSoundSelectionID(manager: manager, fileManager: .default)
        let defaults = UserDefaults.standard
        let generalSound = defaults.object(forKey: NotificationService.general.defaultsKey)
        let buildSound = defaults.object(forKey: NotificationService.build.defaultsKey)
        let generalVolume = defaults.object(forKey: NotificationService.general.volumeDefaultsKey)
        let buildVolume = defaults.object(forKey: NotificationService.build.volumeDefaultsKey)

        manager._testResetPlaybackState()
        manager._testResetSoundFileURLResolutionCache()
        defer {
            stopAllPlayback(manager)
            restore(defaults, key: NotificationService.general.defaultsKey, value: generalSound)
            restore(defaults, key: NotificationService.build.defaultsKey, value: buildSound)
            restore(defaults, key: NotificationService.general.volumeDefaultsKey, value: generalVolume)
            restore(defaults, key: NotificationService.build.volumeDefaultsKey, value: buildVolume)
            manager._testResetSoundFileURLResolutionCache()
        }

        defaults.set(selectionID, forKey: NotificationService.general.defaultsKey)
        defaults.set(selectionID, forKey: NotificationService.build.defaultsKey)
        defaults.set(1.0, forKey: NotificationService.general.volumeDefaultsKey)
        defaults.set(1.0, forKey: NotificationService.build.volumeDefaultsKey)

        #expect(manager.resolveAndPlay(for: .general))
        let generalPlayer = manager._testActiveSound(for: .general)
        #expect(manager._testSoundFileURLResolutionSearchCount == 1)

        #expect(manager.resolveAndPlay(for: .build))
        let buildPlayer = manager._testActiveSound(for: .build)
        #expect(manager._testSoundFileURLResolutionSearchCount == 1)

        #expect(generalPlayer != nil)
        #expect(buildPlayer != nil)
        if let generalPlayer, let buildPlayer {
            #expect(generalPlayer !== buildPlayer)
        }
    }

    @Test func refreshSystemSoundsInvalidatesURLResolutionCache() throws {
        let manager = NotificationSoundManager.shared
        let selectionID = try firstSystemSoundSelectionID(manager: manager, fileManager: .default)

        stopAllPlayback(manager)
        manager._testResetSoundFileURLResolutionCache()
        defer {
            stopAllPlayback(manager)
            manager._testResetSoundFileURLResolutionCache()
        }

        manager.playPreview(soundName: selectionID, volume: 1.0)
        #expect(manager._testSoundFileURLResolutionSearchCount == 1)
        manager.stopPreview()

        manager.refreshSystemSounds()
        manager.playPreview(soundName: selectionID, volume: 1.0)
        #expect(manager._testSoundFileURLResolutionSearchCount == 2)
    }

    private func settlePlaybackDelegateCallbacks() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await Task.yield()
    }

    private func customSoundsDirectory(fileManager: FileManager) -> URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/com.yenchat.yen/sounds", isDirectory: true)
    }

    private func firstSystemSoundURL(fileManager: FileManager) throws -> URL {
        let systemDir = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)
        let files = try fileManager.contentsOfDirectory(atPath: systemDir.path)
        for ext in Self.audioExtensionPriority {
            if let file = files.first(where: {
                ($0 as NSString).pathExtension.lowercased() == ext
            }) {
                return systemDir.appendingPathComponent(file)
            }
        }
        throw NotificationSoundImportTestError.noSystemSoundFound
    }

    private func firstSystemSoundSelectionID(
        manager: NotificationSoundManager,
        fileManager: FileManager
    ) throws -> String {
        let source = try firstSystemSoundURL(fileManager: fileManager)
        let name = source.deletingPathExtension().lastPathComponent
        guard let option = manager.systemSounds.first(where: { $0.name == name }) else {
            throw NotificationSoundImportTestError.noSystemSoundFound
        }
        return option.id
    }

    private func stopAllPlayback(_ manager: NotificationSoundManager) {
        for service in NotificationService.configurableCases {
            manager._testActiveSound(for: service)?.stop()
        }
        manager.stopPreview()
        manager._testResetPlaybackState()
    }

    private func restore(_ defaults: UserDefaults, key: String, value: Any?) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static let audioExtensionPriority = ["m4a", "aiff", "aif", "wav", "mp3", "caf"]
}

private enum NotificationSoundImportTestError: Error {
    case noSystemSoundFound
    case syntheticDecodeFailure
}
