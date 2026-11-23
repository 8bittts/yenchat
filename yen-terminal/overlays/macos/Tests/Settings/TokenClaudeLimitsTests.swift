import Foundation
import Testing
@testable import YEN

/// Claude Code passes its plan limits only to the statusline command, so the token
/// menu shows Claude's live limits through a block YEN adds to that script on request.
@Suite(.serialized)
struct TokenClaudeLimitsTests {
    private static let userScript = """
        #!/bin/bash
        input=$(cat)
        model=$(echo "$input" | jq -r '.model.display_name // empty')
        printf '%s' "$model"
        """

    private func home(command: String? = "bash ~/.claude/statusline.sh", script: String? = userScript) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("claude-limits-" + UUID().uuidString)
        let claude = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        if let command {
            let settings = try JSONSerialization.data(withJSONObject: ["statusLine": ["type": "command", "command": command]])
            try settings.write(to: claude.appendingPathComponent("settings.json"))
        }
        if let script {
            let url = claude.appendingPathComponent("statusline.sh")
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return home
    }

    @Test func theScriptComesFromTheStatusLineCommand() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(TokenClaudeLimits.script(home: home)?.path == home.appendingPathComponent(".claude/statusline.sh").path)
        for command in ["\"$HOME/.claude/statusline.sh\"", "~/.claude/statusline.sh", "/bin/bash $HOME/.claude/statusline.sh"] {
            let other = try self.home(command: command)
            defer { try? FileManager.default.removeItem(at: other) }
            #expect(TokenClaudeLimits.script(home: other)?.lastPathComponent == "statusline.sh", "\(command)")
        }
        let none = try self.home(command: nil)
        defer { try? FileManager.default.removeItem(at: none) }
        #expect(TokenClaudeLimits.script(home: none) == nil)
        #expect(TokenClaudeLimits.state(home: none) == .unavailable)
    }

    @Test func aScriptThatDoesNotKeepItsInputCannotBeHooked() throws {
        let home = try home(script: "#!/bin/bash\njq -r '.model.display_name'\n")
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(TokenClaudeLimits.state(home: home) == .unavailable)
        #expect(throws: TokenClaudeLimits.Failure.self) { try TokenClaudeLimits.install(home: home) }
    }

    @Test func installAddsOneBlockAndRemoveRestoresTheScript() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let url = home.appendingPathComponent(".claude/statusline.sh")
        let original = try String(contentsOf: url, encoding: .utf8)
        #expect(TokenClaudeLimits.state(home: home) == .installable)

        try TokenClaudeLimits.install(home: home)
        try TokenClaudeLimits.install(home: home)
        let installed = try String(contentsOf: url, encoding: .utf8)
        #expect(installed.hasPrefix(original))
        #expect(installed.components(separatedBy: TokenClaudeLimits.begin).count == 2, "One block after two installs")
        #expect(installed.contains("\"$input\""), "The block reads the variable the script already filled")
        #expect(TokenClaudeLimits.state(home: home) == .active)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o755, "The script stays executable")

        try TokenClaudeLimits.uninstall(home: home)
        #expect(try String(contentsOf: url, encoding: .utf8) == original)
        #expect(TokenClaudeLimits.state(home: home) == .installable)
    }

    @Test func installEditsTheFileALinkPointsTo() throws {
        let home = try home(command: "bash ~/.claude/link.sh")
        defer { try? FileManager.default.removeItem(at: home) }
        let link = home.appendingPathComponent(".claude/link.sh")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: home.appendingPathComponent(".claude/statusline.sh"))
        try TokenClaudeLimits.install(home: home)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path).hasSuffix("statusline.sh"))
        let target = try String(contentsOf: home.appendingPathComponent(".claude/statusline.sh"), encoding: .utf8)
        #expect(target.contains(TokenClaudeLimits.begin))
    }

    private func run(_ home: URL, payload: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [home.appendingPathComponent(".claude/statusline.sh").path]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data(payload.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    @Test func theBlockSavesTheLimitsAndLeavesTheStatusLineAlone() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        try TokenClaudeLimits.install(home: home)
        let reset = Int(Date().addingTimeInterval(86_400).timeIntervalSince1970)
        let printed = try run(home, payload: """
            {"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":\(reset)},\
            "seven_day":{"used_percentage":61,"resets_at":\(reset)},\
            "model_scoped":[{"display_name":"Fable","utilization":40,"resets_at":"2099-01-01T00:00:00Z"}],"spend":{"x":1}}}
            """)
        #expect(printed == "Opus", "The user's statusline prints what it printed before")
        let now = Date()
        let meters = TokenClaudeLimits.meters(home: home, now: now)
        #expect(meters.map(\.label) == ["5-hour", "Weekly", "Fable weekly"])
        #expect(meters.map(\.percent) == [12, 61, 40])

        // A later turn that omits the per-model row keeps the one already saved.
        _ = try run(home, payload: #"{"model":{"display_name":"Opus"},"rate_limits":{"seven_day":{"used_percentage":62,"resets_at":\#(reset)}}}"#)
        #expect(TokenClaudeLimits.meters(home: home, now: now).map(\.percent) == [62, 40])
        // A turn without limits writes nothing over the last reading.
        _ = try run(home, payload: #"{"model":{"display_name":"Opus"},"rate_limits":null}"#)
        #expect(TokenClaudeLimits.meters(home: home, now: now).map(\.percent) == [62, 40])
    }

    @Test func savedLimitsWinOverTheCacheAndExpireAtTheirReset() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date()
        let soon = Int(now.addingTimeInterval(3_600).timeIntervalSince1970)
        let past = Int(now.addingTimeInterval(-60).timeIntervalSince1970)
        let file = TokenClaudeLimits.capture(home: home)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"captured_at":1,"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":\#(past)},"seven_day":{"used_percentage":61,"resets_at":\#(soon)}}}"#.utf8).write(to: file)
        let cache = [TokenPlanMeter("Weekly", percent: NSNumber(value: 76), reset: now.addingTimeInterval(60)),
                     TokenPlanMeter("Fable weekly", percent: NSNumber(value: 100), reset: now.addingTimeInterval(60))].compactMap { $0 }
        let merged = TokenClaudeLimits.merged(TokenClaudeLimits.meters(home: home, now: now), cache: cache)
        #expect(merged.map(\.label) == ["Weekly", "Fable weekly"])
        #expect(merged.map(\.percent) == [61, 100])
    }

    @Test func uninstallRemovesTheSavedReading() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        try TokenClaudeLimits.install(home: home)
        let reset = Int(Date().addingTimeInterval(86_400).timeIntervalSince1970)
        _ = try run(home, payload: #"{"rate_limits":{"seven_day":{"used_percentage":61,"resets_at":\#(reset)}}}"#)
        #expect(FileManager.default.fileExists(atPath: TokenClaudeLimits.capture(home: home).path))
        try TokenClaudeLimits.uninstall(home: home)
        #expect(!FileManager.default.fileExists(atPath: TokenClaudeLimits.capture(home: home).path))
        #expect(TokenClaudeLimits.meters(home: home, now: Date()).isEmpty)
    }
}
