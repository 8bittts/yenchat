import Foundation

/// Repairs the `theme` key in the managed config before the engine loads it.
///
/// The engine draws its built-in colors when no `theme` key is set, and it
/// reports an error when the key names a file it cannot open. Both happen
/// without any user action: a first launch has no key, and a release that
/// removes a bundled theme leaves the old name behind. This runs before the
/// engine reads the file, so neither state reaches the terminal.
enum ThemeConfigRepair {
    static let defaultThemeName = "YEN"

    struct Environment {
        let configPath: String
        let userThemesDirectory: String
        let bundledThemesDirectory: String
        /// The other config files the engine loads by default. A theme or a
        /// color key in one of them is the user's own choice and wins.
        let otherConfigPaths: [String]

        static func live(
            processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
            homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
            resourcePath: String = Bundle.main.resourcePath ?? ""
        ) -> Environment {
            let configPath = SettingsController.resolveConfigPath(
                environment: processEnvironment,
                homeDirectory: homeDirectory
            )
            let explicitConfigPath = processEnvironment["YEN_CONFIG_PATH"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let xdgOverride = processEnvironment["XDG_CONFIG_HOME"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let xdgRoot = xdgOverride.hasPrefix("/") ? xdgOverride : "\(homeDirectory)/.config"
            let configDirectory = (configPath as NSString).deletingLastPathComponent
            return Environment(
                configPath: configPath,
                userThemesDirectory: "\(xdgRoot)/yen/themes",
                bundledThemesDirectory: "\(resourcePath)/yen/themes",
                // An explicit config path replaces the default file list.
                otherConfigPaths: explicitConfigPath.isEmpty
                    ? [
                        "\(xdgRoot)/yen/config",
                        "\(xdgRoot)/yen/config.yen",
                        "\(configDirectory)/config",
                    ]
                    : []
            )
        }
    }

    /// Returns the repaired contents, or nil when the file must stay as it is.
    static func repairedContents(
        _ contents: String,
        themeResolves: (String) -> Bool,
        otherConfigFilesExist: Bool
    ) -> String? {
        // A build that does not ship the default theme must never write its name.
        guard themeResolves(defaultThemeName) else { return nil }

        let lines = contents.components(separatedBy: .newlines)
        let themeLineIndex = lines.firstIndex { ManagedConfigDocument.key(from: $0) == "theme" }

        if let themeLineIndex {
            // `theme =` with no value is an explicit reset to the engine default.
            guard let entry = ManagedConfigDocument.entry(from: lines[themeLineIndex]) else { return nil }
            let reference = unquoted(entry.value)
            guard !reference.isEmpty else { return nil }
            // A `light:,dark:` pair and a theme given by path are left to the engine.
            if reference.contains(":") || reference.contains(",") { return nil }
            if reference.hasPrefix("/") || reference.hasPrefix("~") { return nil }
            if themeResolves(reference) { return nil }

            // A user theme saved as `Name.yen` and referenced as `Name` is the
            // user's own theme under the wrong name, not a removed one.
            let suffixed = "\(reference).yen"
            var repaired = lines
            repaired[themeLineIndex] = "theme = \(themeResolves(suffixed) ? suffixed : defaultThemeName)"
            return repaired.joined(separator: "\n")
        }

        // No theme key. Explicit colors here, or any other config file, mean the
        // look is hand-authored, so the default theme must not be laid over it.
        if otherConfigFilesExist { return nil }
        let hasExplicitColors = lines.contains { line in
            guard let key = ManagedConfigDocument.key(from: line) else { return false }
            return ManagedConfigDocument.themeColorKeys.contains(key)
        }
        if hasExplicitColors { return nil }

        if contents.isEmpty { return "theme = \(defaultThemeName)\n" }
        return contents + (contents.hasSuffix("\n") ? "" : "\n") + "theme = \(defaultThemeName)\n"
    }

    /// Repairs the config file in place. Returns true when the file was written.
    @discardableResult
    static func repairConfigFile(
        in environment: Environment,
        fileManager: FileManager = .default
    ) -> Bool {
        let contents: String
        if fileManager.fileExists(atPath: environment.configPath) {
            // An existing file that cannot be read is never overwritten.
            guard let existing = try? String(contentsOfFile: environment.configPath, encoding: .utf8) else {
                return false
            }
            contents = existing
        } else {
            contents = ""
        }

        let themeResolves: (String) -> Bool = { reference in
            [environment.userThemesDirectory, environment.bundledThemesDirectory].contains { directory in
                var isDirectory: ObjCBool = false
                let path = (directory as NSString).appendingPathComponent(reference)
                return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
            }
        }
        guard let repaired = repairedContents(
            contents,
            themeResolves: themeResolves,
            otherConfigFilesExist: environment.otherConfigPaths.contains { fileManager.fileExists(atPath: $0) }
        ) else { return false }

        do {
            try fileManager.createDirectory(
                atPath: (environment.configPath as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try repaired.write(toFile: environment.configPath, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: environment.configPath)
            return true
        } catch {
            return false
        }
    }

    private static func unquoted(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\""))
            || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}
