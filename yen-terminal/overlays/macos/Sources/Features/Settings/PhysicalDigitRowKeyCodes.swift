#if os(macOS)

/// Physical top-row digit key codes in layout order: 1, 2, 3, 4, 5, 6, 7, 8, 9, 0.
///
/// The key-code source stays physical rather than character-derived so Cmd+Option+1-0
/// layout shortcuts and conflict checks keep working on non-US keyboard layouts.
enum PhysicalDigitRowKeyCodes {
    static let keyCodeToIndex: [UInt16: Int] = [
        18: 0,
        19: 1,
        20: 2,
        21: 3,
        23: 4,
        22: 5,
        26: 6,
        28: 7,
        25: 8,
        29: 9,
    ]

    private static let keyCodeByIndex: [Int: UInt16] = Dictionary(
        uniqueKeysWithValues: keyCodeToIndex.map { keyCode, index in
            (index, keyCode)
        }
    )

    static func layoutIndex(forKeyCode keyCode: UInt16) -> Int? {
        keyCodeToIndex[keyCode]
    }

    static func keyCode(forLayoutIndex index: Int) -> UInt16? {
        keyCodeByIndex[index]
    }

    static func keyCode(forDisplayDigit digit: Int) -> UInt16? {
        guard (0...9).contains(digit) else { return nil }
        let layoutIndex = digit == 0 ? 9 : digit - 1
        return keyCode(forLayoutIndex: layoutIndex)
    }

    static func fallbackDigitName(forKeyCode keyCode: UInt16) -> String? {
        guard let layoutIndex = layoutIndex(forKeyCode: keyCode) else { return nil }
        return fallbackDigitName(forLayoutIndex: layoutIndex)
    }

    static func fallbackDigitName(forLayoutIndex index: Int) -> String? {
        guard keyCodeByIndex[index] != nil else { return nil }
        return "\((index + 1) % 10)"
    }
}

#endif
