import Foundation

/// Plan limit alerts: one notification when a pool first reaches 80% and one when it reaches 95%,
/// at most once each per pool window. A window is the pool and its reset time, so the next window
/// alerts again. The fired set is saved, so a relaunch inside the same window stays quiet.
struct TokenLimitAlerts {
    static let enabledKey = "com.yenchat.yen.tokenUsage.limitAlerts"
    static let firedKey = "com.yenchat.yen.tokenUsage.firedLimitAlerts"
    static let warning: Double = 80
    static let critical: Double = 95
    /// Marks a delivered alert, so a click opens the token panel instead of a terminal window.
    static let userInfoKey = "YENTokenLimitAlert"

    struct Alert: Equatable {
        let tool: TokenTool
        let meter: TokenPlanMeter
        let threshold: Double

        var identifier: String { "yen-notification.Usage." + TokenLimitAlerts.key(tool, meter, threshold) }

        /// "Claude Code weekly", "Codex 5-hour", "Claude Code Fable weekly", "Grok weekly".
        var pool: String {
            guard tool != .grok else { return meter.label }
            let label = meter.label == "Weekly" ? "weekly" : meter.label
            return tool.rawValue + " " + label
        }

        var title: String {
            pool + " limit at " + (meter.percent / 100).formatted(.percent.precision(.fractionLength(0)))
        }

        func body(now: Date, calendar: Calendar = .current) -> String {
            let lead = meter.percent >= 100 ? "Limit reached." : threshold >= TokenLimitAlerts.critical ? "Almost out." : nil
            guard let reset = meter.reset else { return lead ?? "Plan usage is high." }
            let when = calendar.isDate(reset, inSameDayAs: now)
                ? reset.formatted(date: .omitted, time: .shortened)
                : reset.formatted(.dateTime.weekday(.wide).hour().minute())
            return [lead, "Resets " + when + "."].compactMap { $0 }.joined(separator: " ")
        }
    }

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    static func key(_ tool: TokenTool, _ meter: TokenPlanMeter, _ threshold: Double) -> String {
        let reset = meter.reset.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
        return [tool.rawValue, meter.label, String(Int(threshold)), reset].joined(separator: "|")
    }

    /// The alerts this reading raises. A pool past both thresholds raises only the higher one and
    /// marks both, so a launch at 97% shows one alert. Keys of finished windows are dropped.
    static func due(plans: [TokenTool: [TokenPlanMeter]], fired: inout Set<String>, now: Date) -> [Alert] {
        fired = fired.filter { key in
            guard let epoch = key.split(separator: "|").last.flatMap({ Double($0) }), epoch > 0 else { return true }
            return Date(timeIntervalSince1970: epoch) > now
        }
        var alerts: [Alert] = []
        for tool in TokenTool.allCases {
            for meter in plans[tool] ?? [] where meter.isCurrent(at: now) {
                let crossed = [warning, critical].filter { meter.percent >= $0 }
                let fresh = crossed.filter { fired.insert(key(tool, meter, $0)).inserted }
                if let top = fresh.max(), top == crossed.max() {
                    alerts.append(Alert(tool: tool, meter: meter, threshold: top))
                }
            }
        }
        return alerts
    }

    /// Reads and writes the saved fired set around `due`.
    static func evaluate(plans: [TokenTool: [TokenPlanMeter]], now: Date = Date(),
                         defaults: UserDefaults = .standard) -> [Alert] {
        guard isEnabled(defaults) else { return [] }
        var fired = Set(defaults.stringArray(forKey: firedKey) ?? [])
        let before = fired
        let alerts = due(plans: plans, fired: &fired, now: now)
        if fired != before { defaults.set(fired.sorted(), forKey: firedKey) }
        return alerts
    }

    /// Reset All Settings turns the alerts back on and forgets which windows alerted.
    static func reset(defaults: UserDefaults = .standard) {
        for key in [enabledKey, firedKey] { defaults.removeObject(forKey: key) }
    }
}
