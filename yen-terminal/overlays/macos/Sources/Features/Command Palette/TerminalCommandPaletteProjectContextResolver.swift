import CryptoKit
import Foundation

enum TerminalCommandPaletteProjectContextResolver {
    private static let rootMarkers = [
        ".git",
        "package.json",
        "go.mod",
        "Cargo.toml",
        "pyproject.toml",
        "requirements.txt",
        "setup.py",
        "Package.swift",
        "build.zig",
        ".devcontainer.json",
        "Makefile",
    ]

    private static let contextMarkers = Set(rootMarkers + [
        "bun.lock", "bun.lockb", "biome.json", "tsconfig.json", "next.config.ts", "next.config.js",
        "Dockerfile", ".devcontainer", "package-lock.json", "pnpm-lock.yaml", "yarn.lock",
    ])
    private static let markerSpellings = Dictionary(uniqueKeysWithValues: contextMarkers.map { ($0.lowercased(), $0) })

    static func resolve(
        pwd: String?,
        directoryEntries: (String) -> Set<String> = existingEntryNames(at:)
    ) -> TerminalCommandPaletteContext {
        guard let startPath = LocalPathResolver.canonicalPath(pwd) else { return .empty }
        var listings: [String: Set<String>] = [:]
        func entries(at path: String) -> Set<String> {
            if let cached = listings[path] { return cached }
            let names = directoryEntries(path)
            listings[path] = names
            return names
        }
        guard let root = findProjectRoot(startPath: startPath, entries: entries(at:)) else { return .empty }
        let names = entries(at: root)
        return TerminalCommandPaletteContext(projectRoot: root,
            runtime: detectRuntimeContext(names: names), tooling: detectToolingContext(names: names))
    }

    static func projectHash(root: String) -> String {
        let digest = SHA256.hash(data: Data(root.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Listing names must preserve fileExists semantics for dangling links and unreadable parents.
    static func existingEntryNames(at path: String) -> Set<String> {
        let manager = FileManager.default
        let root = URL(fileURLWithPath: path)
        guard let urls = try? manager.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            return Set(contextMarkers.filter { manager.fileExists(atPath: root.appendingPathComponent($0).path) })
        }
        return Set(urls.compactMap { url in
            guard let marker = markerSpellings[url.lastPathComponent.lowercased()] else { return nil }
            // Preserve fileExists behavior on both case-sensitive and case-insensitive volumes.
            if marker != url.lastPathComponent {
                return manager.fileExists(atPath: root.appendingPathComponent(marker).path) ? marker : nil
            }
            let isLink = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink
            if isLink != false && !manager.fileExists(atPath: url.path) { return nil }
            return marker
        })
    }

    private static func findProjectRoot(startPath: String, entries: (String) -> Set<String>) -> String? {
        var currentURL = URL(fileURLWithPath: startPath)
        let fileManager = FileManager.default

        if !fileManager.directoryExists(atPath: startPath) {
            currentURL.deleteLastPathComponent()
        }

        let fallback = currentURL.path
        while true {
            guard !Task.isCancelled else { return nil }
            let currentPath = currentURL.path
            if rootMarkers.contains(where: entries(currentPath).contains) {
                return currentPath
            }

            if currentPath == "/" {
                return fallback
            }

            let parent = currentURL.deletingLastPathComponent()
            if parent.path == currentPath {
                return fallback
            }
            currentURL = parent
        }
    }

    private static func detectRuntimeContext(names: Set<String>) -> Set<String> {
        var context: Set<String> = []
        if names.contains("package.json") {
            if names.contains("bun.lockb") ||
                names.contains("bun.lock") {
                context.insert("bun")
            }
            context.insert("node")
        }
        if names.contains("go.mod") {
            context.insert("go")
        }
        if names.contains("Cargo.toml") {
            context.insert("rust")
        }
        if names.contains("pyproject.toml") ||
            names.contains("requirements.txt") {
            context.insert("python")
        }
        if names.contains("Package.swift") {
            context.insert("swift")
        }
        if names.contains("build.zig") {
            context.insert("zig")
        }
        if context.isEmpty {
            context.insert("unknown")
        }
        return context
    }

    private static func detectToolingContext(names: Set<String>) -> Set<String> {
        var context: Set<String> = []
        if names.contains(".git") {
            context.insert("git")
        }
        if names.contains("biome.json") {
            context.insert("biome")
        }
        if names.contains("tsconfig.json") {
            context.insert("typescript")
        }
        if names.contains("next.config.ts") ||
            names.contains("next.config.js") {
            context.insert("nextjs")
        }
        if names.contains("Dockerfile") ||
            names.contains(".devcontainer") ||
            names.contains(".devcontainer.json") {
            context.insert("container")
        }
        if names.contains("Makefile") {
            context.insert("make")
        }
        if names.contains("package-lock.json") {
            context.insert("npm")
        }
        if names.contains("pnpm-lock.yaml") {
            context.insert("pnpm")
        }
        if names.contains("yarn.lock") {
            context.insert("yarn")
        }
        if names.contains("bun.lock") ||
            names.contains("bun.lockb") {
            context.insert("bun")
        }
        if names.contains("go.mod") {
            context.insert("go-mod")
        }
        if names.contains("Cargo.toml") {
            context.insert("cargo")
        }
        if names.contains("pyproject.toml") {
            context.insert("pyproject")
        }
        if context.isEmpty {
            context.insert("minimal")
        }
        return context
    }
}

private extension FileManager {
    func directoryExists(atPath path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
