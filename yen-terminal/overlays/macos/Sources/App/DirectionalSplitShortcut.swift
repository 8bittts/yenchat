import AppKit

enum DirectionalSplitDirection: Equatable {
    case left
    case right
    case down
    case up

    var selector: Selector {
        switch self {
        case .left: #selector(BaseTerminalController.splitLeft(_:))
        case .right: #selector(BaseTerminalController.splitRight(_:))
        case .down: #selector(BaseTerminalController.splitDown(_:))
        case .up: #selector(BaseTerminalController.splitUp(_:))
        }
    }
}

enum DirectionalSplitShortcut {
    private static let arrowDirections: [(keyCode: UInt16, direction: DirectionalSplitDirection)] = [
        (123, .left),
        (124, .right),
        (125, .down),
        (126, .up),
    ]

    static func direction(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags,
        pressedKeyCodes: Set<UInt16>
    ) -> DirectionalSplitDirection? {
        let shortcutModifiers = modifierFlags.intersection([.command, .control, .option, .shift])
        guard charactersIgnoringModifiers?.lowercased() == "d",
              shortcutModifiers == .command else {
            return nil
        }

        let heldDirections = arrowDirections.compactMap { arrow in
            pressedKeyCodes.contains(arrow.keyCode) ? arrow.direction : nil
        }
        guard heldDirections.count == 1 else { return nil }
        return heldDirections[0]
    }

    static func direction(for event: NSEvent) -> DirectionalSplitDirection? {
        guard !event.isARepeat else { return nil }
        let pressedKeyCodes = Set(arrowDirections.compactMap { arrow in
            CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(arrow.keyCode))
                ? arrow.keyCode
                : nil
        })
        return direction(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags,
            pressedKeyCodes: pressedKeyCodes
        )
    }
}

extension AppDelegate {
    @MainActor func directionalSplitSelector(for event: NSEvent) -> Selector? {
        DirectionalSplitShortcut.direction(for: event)?.selector
    }
}
