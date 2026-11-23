import Foundation

/// Claude Code passes its plan limits (`rate_limits`) only to the statusline command and keeps no
/// current copy on disk; the cache in `~/.claude.json` can be days old. On request from Settings, YEN
/// appends one marked block to the user's statusline script. The block saves those limits to
/// `~/.local/state/yen/claude-limits.json`, which only the token menu reads. Removing it from Settings
/// deletes the block and the saved file. Nothing else is written, and no other app's file is read.
enum TokenClaudeLimits {
    static let begin = "# BEGIN YEN-CLAUDE-LIMITS"
    static let end = "# END YEN-CLAUDE-LIMITS"

    enum State: Equatable { case active, installable, unavailable }

    enum Failure: Error { case noStatusLine, noInputVariable }

    static func capture(home: URL) -> URL {
        home.appendingPathComponent(".local/state/yen/claude-limits.json")
    }

    /// The script `statusLine.command` runs, such as `bash ~/.claude/statusline.sh`: the last word
    /// ending in `.sh`, or the only word. Links resolve to the file they point to.
    static func script(home: URL) -> URL? {
        guard let data = try? Data(contentsOf: home.appendingPathComponent(".claude/settings.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let line = root["statusLine"] as? [String: Any], (line["type"] as? String ?? "command") == "command",
              let command = line["command"] as? String else { return nil }
        let words = command.split(whereSeparator: \.isWhitespace).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
        guard var path = words.last(where: { $0.hasSuffix(".sh") }) ?? (words.count == 1 ? words.first : nil) else { return nil }
        for prefix in ["~/", "$HOME/", "${HOME}/"] where path.hasPrefix(prefix) {
            path = home.appendingPathComponent(String(path.dropFirst(prefix.count))).path
        }
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath()
    }

    /// The variable the script reads its input into (`input=$(cat)`). The block reuses it, because
    /// reading standard input a second time would leave the user's statusline with nothing.
    static func inputVariable(in script: String) -> String? {
        for line in script.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.range(of: #"^[A-Za-z_][A-Za-z0-9_]*=\$\(cat\)$"#, options: .regularExpression) != nil,
                  let name = text.split(separator: "=").first else { continue }
            return String(name)
        }
        return nil
    }

    static func state(home: URL) -> State {
        guard let url = script(home: home), let text = try? String(contentsOf: url, encoding: .utf8) else { return .unavailable }
        if text.contains(begin) { return .active }
        return inputVariable(in: text) == nil ? .unavailable : .installable
    }

    static func install(home: URL) throws {
        guard let url = script(home: home) else { throw Failure.noStatusLine }
        let text = removing(from: try String(contentsOf: url, encoding: .utf8))
        guard let variable = inputVariable(in: text) else { throw Failure.noInputVariable }
        // One newline starts the block on its own line; `removing` takes back exactly that newline.
        try write(text + "\n" + block(variable: variable), to: url)
    }

    static func uninstall(home: URL) throws {
        if let url = script(home: home), let text = try? String(contentsOf: url, encoding: .utf8), text.contains(begin) {
            try write(removing(from: text), to: url)
        }
        try? FileManager.default.removeItem(at: capture(home: home))
    }

    /// Writes through a temporary file and keeps the script's permissions, so it stays executable.
    private static func write(_ text: String, to url: URL) throws {
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
        try text.write(to: url, atomically: true, encoding: .utf8)
        if let mode { try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path) }
    }

    /// Removes the block and the newline `install` put before it, leaving the rest byte for byte.
    static func removing(from script: String) -> String {
        guard let start = script.range(of: "\n" + begin) ?? script.range(of: begin),
              let finish = script.range(of: end + "\n", range: start.upperBound..<script.endIndex)
                ?? script.range(of: end, range: start.upperBound..<script.endIndex) else { return script }
        return String(script[..<start.lowerBound]) + script[finish.upperBound...]
    }

    /// The saved object is `{captured_at, rate_limits: {five_hour, seven_day, model_scoped}}`. A turn
    /// without limits writes nothing, and one that omits `model_scoped` keeps the saved rows.
    static func block(variable: String) -> String {
        #"""
        \#(begin) (added by YEN; turn off Claude Plan Limits in YEN Settings to remove it)
        # Saves Claude Code's plan limits for YEN's token menu, which reads only this file.
        if command -v jq >/dev/null 2>&1; then
          __yen_file="$HOME/.local/state/yen/claude-limits.json"
          __yen_next=$(printf '%s' "$\#(variable)" | jq -c 'select((.rate_limits | type) == "object") | {captured_at: (now | floor), rate_limits: (.rate_limits | {five_hour, seven_day, model_scoped} | with_entries(select(.value != null)))} | select(.rate_limits != {})' 2>/dev/null)
          if [ -n "$__yen_next" ] && [ -f "$__yen_file" ]; then
            __yen_next=$(printf '%s' "$__yen_next" | jq -c --slurpfile old "$__yen_file" '($old[0].rate_limits.model_scoped // null) as $kept | if (.rate_limits | has("model_scoped")) or $kept == null then . else .rate_limits.model_scoped = $kept end' 2>/dev/null) || __yen_next=""
          fi
          if [ -n "$__yen_next" ] && mkdir -p "${__yen_file%/*}" 2>/dev/null; then
            printf '%s\n' "$__yen_next" > "$__yen_file.tmp" 2>/dev/null && mv -f "$__yen_file.tmp" "$__yen_file" 2>/dev/null
          fi
          unset __yen_file __yen_next
        fi
        \#(end)

        """#
    }

    /// Current windows from the saved file: `five_hour` and `seven_day` carry `used_percentage` and
    /// `resets_at` in epoch seconds; `model_scoped` rows carry `utilization` and an ISO 8601 `resets_at`.
    /// Both percentages are 0 to 100. A window past its reset is dropped, whatever the file's age.
    static func meters(home: URL, now: Date) -> [TokenPlanMeter] {
        guard let data = try? Data(contentsOf: capture(home: home)),
              let root = try? JSONSerialization.jsonObject(with: data) as? TokenRecord.Object,
              let limits = root["rate_limits"] as? TokenRecord.Object else { return [] }
        var meters = [("five_hour", "5-hour"), ("seven_day", "Weekly")].compactMap { key, label -> TokenPlanMeter? in
            guard let row = limits[key] as? TokenRecord.Object, let end = (row["resets_at"] as? NSNumber)?.doubleValue else { return nil }
            return TokenPlanMeter(label, percent: row["used_percentage"], reset: Date(timeIntervalSince1970: end))
        }
        for row in limits["model_scoped"] as? [TokenRecord.Object] ?? [] {
            guard let name = row["display_name"] as? String, !name.isEmpty,
                  let meter = TokenPlanMeter(name + " weekly", percent: row["utilization"], reset: TokenRecord.date(row["resets_at"])),
                  !meters.contains(where: { $0.label == meter.label }) else { continue }
            meters.append(meter)
        }
        return meters.filter { $0.reset.map { $0 > now } ?? false }
    }

    /// The saved limits, then any cached window the saved file does not name.
    static func merged(_ saved: [TokenPlanMeter], cache: [TokenPlanMeter]) -> [TokenPlanMeter] {
        saved + cache.filter { meter in !saved.contains { $0.label == meter.label } }
    }
}
