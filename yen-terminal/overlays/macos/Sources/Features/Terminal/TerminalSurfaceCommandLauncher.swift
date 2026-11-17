import AppKit
import YENKit

@MainActor
enum TerminalSurfaceCommandLauncher {
    nonisolated static let dispatchDelay: TimeInterval = 0.05
    nonisolated static let fileBrowserCommand = "y"
    nonisolated static let gitTUICommand = "yengit"

    struct CommandInputStep: Equatable {
        let key: YEN.Input.Key
        let text: String
    }

    static func commandInputSteps(for command: String) -> [CommandInputStep] {
        command.compactMap { character in
            switch character {
            case " ":
                return CommandInputStep(key: .space, text: " ")
            case "a"..."z":
                return CommandInputStep(
                    key: YEN.Input.Key(rawValue: String(character)) ?? .space,
                    text: String(character)
                )
            case "A"..."Z":
                let lowercased = String(character).lowercased()
                return CommandInputStep(
                    key: YEN.Input.Key(rawValue: lowercased) ?? .space,
                    text: String(character)
                )
            case "0":
                return CommandInputStep(key: .digit0, text: "0")
            case "1":
                return CommandInputStep(key: .digit1, text: "1")
            case "2":
                return CommandInputStep(key: .digit2, text: "2")
            case "3":
                return CommandInputStep(key: .digit3, text: "3")
            case "4":
                return CommandInputStep(key: .digit4, text: "4")
            case "5":
                return CommandInputStep(key: .digit5, text: "5")
            case "6":
                return CommandInputStep(key: .digit6, text: "6")
            case "7":
                return CommandInputStep(key: .digit7, text: "7")
            case "8":
                return CommandInputStep(key: .digit8, text: "8")
            case "9":
                return CommandInputStep(key: .digit9, text: "9")
            case "-":
                return CommandInputStep(key: .minus, text: "-")
            case ".":
                return CommandInputStep(key: .period, text: ".")
            case "/":
                return CommandInputStep(key: .slash, text: "/")
            case ":":
                return CommandInputStep(key: .semicolon, text: ":")
            case "=":
                return CommandInputStep(key: .equal, text: "=")
            default:
                return nil
            }
        }
    }

    static func launchEvents(
        for command: String,
        establishBoundary: Bool = true
    ) -> [YEN.Input.KeyEvent] {
        var events: [YEN.Input.KeyEvent] = []
        if establishBoundary {
            events.append(YEN.Input.KeyEvent(key: .c, action: .press, mods: .ctrl))
        }

        events.append(
            contentsOf: commandInputSteps(for: command).map {
                YEN.Input.KeyEvent(key: $0.key, action: .press, text: $0.text)
            }
        )
        events.append(YEN.Input.KeyEvent(key: .enter, action: .press, text: "\r"))
        return events
    }

    static func nextResponderTarget<T: NSResponder>(
        from responder: NSResponder?,
        as type: T.Type = T.self
    ) -> T? {
        var current = responder
        while let unwrapped = current {
            if let target = unwrapped as? T {
                return target
            }
            current = unwrapped.nextResponder
        }
        return nil
    }

    static func resolvedTarget<T: NSResponder>(
        firstResponder: NSResponder?,
        fallback: T?
    ) -> T? {
        nextResponderTarget(from: firstResponder, as: T.self) ?? fallback
    }

    static func resolvedSurface(in window: NSWindow?) -> YEN.SurfaceView? {
        guard let window else { return nil }
        let fallback = (window.windowController as? BaseTerminalController)?.focusedSurface
        return resolvedTarget(firstResponder: window.firstResponder, fallback: fallback)
    }

    @discardableResult
    static func launchFileBrowser(in window: NSWindow?) -> Bool {
        guard let surfaceView = resolvedSurface(in: window) else { return false }
        return dispatch(command: fileBrowserCommand, to: surfaceView)
    }

    @discardableResult
    static func launchGitTUI(in window: NSWindow?) -> Bool {
        guard let surfaceView = resolvedSurface(in: window) else { return false }
        return dispatch(command: gitTUICommand, to: surfaceView)
    }

    @discardableResult
    static func dispatch(
        command: String,
        to surfaceView: YEN.SurfaceView,
        establishBoundary: Bool = true,
        delay: TimeInterval = dispatchDelay
    ) -> Bool {
        guard let surfaceModel = surfaceView.surfaceModel else { return false }
        dispatch(command: command, to: surfaceModel, establishBoundary: establishBoundary, delay: delay)
        return true
    }

    static func dispatch(
        command: String,
        to surfaceModel: YEN.Surface,
        establishBoundary: Bool = true,
        delay: TimeInterval = dispatchDelay
    ) {
        let events = launchEvents(for: command, establishBoundary: establishBoundary)
        guard !events.isEmpty else { return }

        if establishBoundary, let boundaryEvent = events.first {
            surfaceModel.sendKeyEvent(boundaryEvent)
        }

        let followUpEvents = establishBoundary ? Array(events.dropFirst()) : events
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { @MainActor in
                for event in followUpEvents {
                    surfaceModel.sendKeyEvent(event)
                }
            }
        }
    }
}
