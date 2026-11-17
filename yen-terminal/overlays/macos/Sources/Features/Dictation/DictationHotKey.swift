import Cocoa

/// Detects Option+Space hotkey for dictation (hold to speak, release to transcribe).
final class DictationHotKey {
    static let shared = DictationHotKey()

    enum HotkeyReleaseReason: Equatable {
        case spaceKeyUp
        case modifierFlagsChanged

        var logReason: String {
            switch self {
            case .spaceKeyUp:
                return "space-key-up"
            case .modifierFlagsChanged:
                return "modifier-flags-changed"
            }
        }
    }

    struct HotkeyEventResolution: Equatable {
        let shouldBeginPress: Bool
        let releaseReason: HotkeyReleaseReason?
        let consumeEvent: Bool

        static let passthrough = Self(
            shouldBeginPress: false,
            releaseReason: nil,
            consumeEvent: false
        )
    }

    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?
    var isPressed: Bool { isHotkeyPressed }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var healthTimer: Timer?
    private var isHotkeyPressed = false
    private var pressedStateRecoveryPending = false

    // Space key virtual keycode
    private let spaceKeyCode: CGKeyCode = 0x31
    private let permissionRetryInterval: TimeInterval = 5.0
    private let healthCheckInterval: TimeInterval = 2.0

    private init() {}

    deinit {
        stop()
    }

    /// Explicitly request the macOS Accessibility trust prompt.
    /// Called only from user-initiated actions (Settings / onboarding),
    /// never automatically at app startup.
    func requestAccessibilityPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Start listening for Option+Space hotkey.
    func start() {
        startHealthMonitoringIfNeeded()
        if let tap = eventTap {
            if !isEventTapHealthy(tap) {
                rebuildEventTap(reason: "start-health-check")
            } else if pressedStateRecoveryPending {
                reconcilePressedStateWithSystemInput(reason: "start-recovery")
            }
            return
        }

        guard AXIsProcessTrusted() else {
            startPermissionRetryTimerIfNeeded()
            return
        }

        retryTimer?.invalidate()
        retryTimer = nil

        // Create event tap for key events
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let handler = Unmanaged<DictationHotKey>.fromOpaque(refcon).takeUnretainedValue()
                return handler.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("DictationHotKey: Failed to create event tap, retrying in 5s")
            startPermissionRetryTimerIfNeeded()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        if pressedStateRecoveryPending {
            reconcilePressedStateWithSystemInput(reason: "tap-started-recovery")
        }
    }

    /// Stop listening for hotkey.
    func stop() {
        stopHealthMonitoring()
        retryTimer?.invalidate()
        retryTimer = nil
        pressedStateRecoveryPending = false
        stopTapResources()
    }

    /// Handle incoming events.
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if disabled
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            recoverTapFromDisableEvent(type: type)
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let reducedFlags = flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift])
        let resolution = Self.hotkeyEventResolution(
            type: type,
            keyCode: keyCode,
            reducedFlags: reducedFlags,
            isHotkeyPressed: isHotkeyPressed,
            spaceKeyCode: spaceKeyCode
        )

        if resolution.shouldBeginPress {
            isHotkeyPressed = true
            DispatchQueue.main.async {
                self.onHotkeyDown?()
            }
        }

        if let releaseReason = resolution.releaseReason {
            emitHotkeyUpIfNeeded(reason: releaseReason.logReason)
        }

        if resolution.consumeEvent {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func startPermissionRetryTimerIfNeeded() {
        guard retryTimer == nil else { return }
        let timer = Timer(timeInterval: permissionRetryInterval, repeats: true) { [weak self] _ in
            self?.start()
        }
        timer.tolerance = 0.5
        // Common mode so permission-retry recovery keeps firing during tracking loops.
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    private func startHealthMonitoringIfNeeded() {
        guard healthTimer == nil else { return }
        let timer = Timer(timeInterval: healthCheckInterval, repeats: true) { [weak self] _ in
            self?.validateTapHealth()
        }
        timer.tolerance = 0.25
        // Common mode so tap-health checks keep firing during tracking loops.
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    private func stopHealthMonitoring() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    private func validateTapHealth() {
        guard AXIsProcessTrusted() else {
            if eventTap != nil {
                print("DictationHotKey: Accessibility permission lost, stopping event tap")
                stopTapResources()
                if Self.shouldEmitHotkeyUpOnAccessibilityTrustLoss(isHotkeyPressed: isHotkeyPressed) {
                    emitHotkeyUpIfNeeded(reason: "accessibility-trust-loss")
                } else {
                    isHotkeyPressed = false
                }
            }
            startPermissionRetryTimerIfNeeded()
            return
        }

        retryTimer?.invalidate()
        retryTimer = nil

        guard let tap = eventTap else {
            start()
            return
        }

        guard isEventTapHealthy(tap) else {
            rebuildEventTap(reason: "health-timer")
            return
        }

        if pressedStateRecoveryPending {
            reconcilePressedStateWithSystemInput(reason: "health-recovery-poll")
        }
    }

    private func recoverTapFromDisableEvent(type: CGEventType) {
        guard let tap = eventTap else {
            start()
            return
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        if !isEventTapHealthy(tap) {
            rebuildEventTap(reason: "\(type)")
            return
        }
        if Self.shouldQueuePressedStateRecovery(isHotkeyPressed: isHotkeyPressed) {
            pressedStateRecoveryPending = true
        }
        reconcilePressedStateWithSystemInput(reason: "tap-disabled-recovery")
    }

    private func rebuildEventTap(reason: String) {
        print("DictationHotKey: rebuilding event tap (\(reason))")
        if Self.shouldQueuePressedStateRecovery(isHotkeyPressed: isHotkeyPressed) {
            pressedStateRecoveryPending = true
        }
        stopTapResources()
        start()
    }

    private func stopTapResources() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func isEventTapHealthy(_ tap: CFMachPort) -> Bool {
        CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap)
    }

    private func reconcilePressedStateWithSystemInput(reason: String) {
        defer { pressedStateRecoveryPending = false }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let isSpaceKeyDown = CGEventSource.keyState(.combinedSessionState, key: spaceKeyCode)
        guard Self.shouldSynthesizeHotkeyUp(
            isHotkeyPressed: isHotkeyPressed,
            isSpaceKeyDown: isSpaceKeyDown,
            keyboardFlags: flags
        ) else { return }

        emitHotkeyUpIfNeeded(reason: reason)
    }

    static func shouldSynthesizeHotkeyUp(
        isHotkeyPressed: Bool,
        isSpaceKeyDown: Bool,
        keyboardFlags: CGEventFlags
    ) -> Bool {
        guard isHotkeyPressed else { return false }
        _ = keyboardFlags
        // Recovery synthesis is intentionally conservative. Normal Option/Space release
        // ordering is handled by event callbacks; recovery only closes sessions once the
        // physical Space key is no longer held.
        return !isSpaceKeyDown
    }

    static func hotkeyEventResolution(
        type: CGEventType,
        keyCode: CGKeyCode,
        reducedFlags: CGEventFlags,
        isHotkeyPressed: Bool,
        spaceKeyCode: CGKeyCode = 0x31
    ) -> HotkeyEventResolution {
        let isExactOptionHotkey = reducedFlags == .maskAlternate

        if keyCode == spaceKeyCode && isExactOptionHotkey {
            if type == .keyDown {
                return HotkeyEventResolution(
                    shouldBeginPress: !isHotkeyPressed,
                    releaseReason: nil,
                    consumeEvent: true
                )
            }
            if type == .keyUp && isHotkeyPressed {
                return HotkeyEventResolution(
                    shouldBeginPress: false,
                    releaseReason: .spaceKeyUp,
                    consumeEvent: true
                )
            }
        }

        if type == .flagsChanged && !isExactOptionHotkey && isHotkeyPressed {
            return HotkeyEventResolution(
                shouldBeginPress: false,
                releaseReason: .modifierFlagsChanged,
                consumeEvent: false
            )
        }

        return .passthrough
    }

    static func shouldQueuePressedStateRecovery(isHotkeyPressed: Bool) -> Bool {
        isHotkeyPressed
    }

    static func shouldEmitHotkeyUpOnAccessibilityTrustLoss(isHotkeyPressed: Bool) -> Bool {
        isHotkeyPressed
    }

    private func emitHotkeyUpIfNeeded(reason: String) {
        guard isHotkeyPressed else { return }
        print("DictationHotKey: hotkey released (\(reason))")
        isHotkeyPressed = false
        DispatchQueue.main.async {
            self.onHotkeyUp?()
        }
    }
}
