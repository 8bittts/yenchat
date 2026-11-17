import Foundation
import Testing
@testable import YEN

/// The engine draws built-in colors without a `theme` key and reports an error
/// for a theme file it cannot open. A first launch has no key, and a release
/// that drops a bundled theme leaves the old name in every config that used it.
@Suite(.serialized)
struct ThemeConfigRepairTests {
    private let shipped: Set<String> = ["YEN", "Dracula", "Mine.yen"]

    private func repaired(
        _ contents: String,
        shipped: Set<String>? = nil,
        otherConfigFilesExist: Bool = false
    ) -> String? {
        let available = shipped ?? self.shipped
        return ThemeConfigRepair.repairedContents(
            contents,
            themeResolves: { available.contains($0) },
            otherConfigFilesExist: otherConfigFilesExist
        )
    }

    @Test func emptyConfigGetsTheDefaultTheme() {
        #expect(repaired("") == "theme = YEN\n")
    }

    @Test func configWithoutAThemeKeepsItsKeysAndGainsTheDefault() {
        #expect(repaired("font-size = 15\n# note") == "font-size = 15\n# note\ntheme = YEN\n")
    }

    @Test func removedThemeIsReplacedInPlace() {
        #expect(
            repaired("font-size = 15\ntheme = Hot Dog Stand\nwindow-padding-x = 4")
                == "font-size = 15\ntheme = YEN\nwindow-padding-x = 4"
        )
        #expect(repaired("theme = \"Hot Dog Stand\"") == "theme = YEN")
    }

    @Test func userThemeReferencedWithoutItsSuffixIsPointedAtTheFile() {
        // `Mine.yen` exists; `theme = Mine` is the reference Settings wrote before
        // it learned to write file names. Keep the user's theme, not the default.
        #expect(repaired("theme = Mine\nfont-size = 15") == "theme = Mine.yen\nfont-size = 15")
    }

    @Test func resolvableThemesAreLeftAlone() {
        #expect(repaired("theme = Dracula") == nil)
        #expect(repaired("theme = \"Dracula\"") == nil)
        #expect(repaired("theme = Mine.yen") == nil)
        #expect(repaired("theme = YEN") == nil)
    }

    @Test func themesTheEngineResolvesAnotherWayAreLeftAlone() {
        #expect(repaired("theme = light:Gone Light,dark:Gone Dark") == nil)
        #expect(repaired("theme = /Users/me/themes/Gone") == nil)
        #expect(repaired("theme = ~/themes/Gone") == nil)
        // An empty value is an explicit reset to the engine default.
        #expect(repaired("theme =") == nil)
    }

    @Test func handAuthoredColorsAreNeverCoveredByTheDefault() {
        #expect(repaired("background = #000000\nforeground = #ffffff") == nil)
        #expect(repaired("palette = 0=#000000") == nil)
        #expect(repaired("font-size = 15", otherConfigFilesExist: true) == nil)
    }

    @Test func buildWithoutTheDefaultThemeWritesNothing() {
        // The Debug and test bundles hold no `YEN` theme file. Writing its name
        // there would create the very error this repair removes.
        #expect(repaired("", shipped: ["Dracula"]) == nil)
        #expect(repaired("theme = Hot Dog Stand", shipped: ["Dracula"]) == nil)
    }

    @Test func repairsTheFileBeforeTheEngineReadsIt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yen-theme-repair-\(UUID().uuidString)", isDirectory: true)
        let bundled = root.appendingPathComponent("bundled", isDirectory: true)
        let user = root.appendingPathComponent("user", isDirectory: true)
        let configURL = root.appendingPathComponent("support/config.yen")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try "background = #262b36\n".write(
            to: bundled.appendingPathComponent("YEN"), atomically: true, encoding: .utf8
        )
        try "background = #101010\n".write(
            to: user.appendingPathComponent("Mine.yen"), atomically: true, encoding: .utf8
        )
        let environment = ThemeConfigRepair.Environment(
            configPath: configURL.path,
            userThemesDirectory: user.path,
            bundledThemesDirectory: bundled.path,
            otherConfigPaths: [root.appendingPathComponent("xdg/config.yen").path]
        )

        // First launch: no file yet.
        #expect(ThemeConfigRepair.repairConfigFile(in: environment))
        #expect(try String(contentsOf: configURL, encoding: .utf8) == "theme = YEN\n")
        let permissions = try FileManager.default.attributesOfItem(atPath: configURL.path)[.posixPermissions]
        #expect((permissions as? NSNumber)?.intValue == 0o600)

        // A second launch changes nothing.
        #expect(!ThemeConfigRepair.repairConfigFile(in: environment))

        // A theme removed from the bundle is replaced; a user theme file is kept.
        try "font-size = 15\ntheme = Hot Dog Stand\n".write(to: configURL, atomically: true, encoding: .utf8)
        #expect(ThemeConfigRepair.repairConfigFile(in: environment))
        #expect(try String(contentsOf: configURL, encoding: .utf8) == "font-size = 15\ntheme = YEN\n")

        try "theme = Mine.yen\n".write(to: configURL, atomically: true, encoding: .utf8)
        #expect(!ThemeConfigRepair.repairConfigFile(in: environment))
        #expect(try String(contentsOf: configURL, encoding: .utf8) == "theme = Mine.yen\n")
    }

    @Test func liveEnvironmentMirrorsTheFilesTheEngineLoads() {
        let defaults = ThemeConfigRepair.Environment.live(
            processEnvironment: [:],
            homeDirectory: "/Users/tester",
            resourcePath: "/Apps/YEN.app/Contents/Resources"
        )
        #expect(defaults.configPath == "/Users/tester/Library/Application Support/com.yenchat.yen/config.yen")
        #expect(defaults.userThemesDirectory == "/Users/tester/.config/yen/themes")
        #expect(defaults.bundledThemesDirectory == "/Apps/YEN.app/Contents/Resources/yen/themes")
        #expect(defaults.otherConfigPaths == [
            "/Users/tester/.config/yen/config",
            "/Users/tester/.config/yen/config.yen",
            "/Users/tester/Library/Application Support/com.yenchat.yen/config",
        ])

        let explicit = ThemeConfigRepair.Environment.live(
            processEnvironment: ["YEN_CONFIG_PATH": "/tmp/one.yen", "XDG_CONFIG_HOME": "/xdg"],
            homeDirectory: "/Users/tester",
            resourcePath: "/Apps/YEN.app/Contents/Resources"
        )
        #expect(explicit.configPath == "/tmp/one.yen")
        #expect(explicit.userThemesDirectory == "/xdg/yen/themes")
        #expect(explicit.otherConfigPaths.isEmpty)
    }
}
