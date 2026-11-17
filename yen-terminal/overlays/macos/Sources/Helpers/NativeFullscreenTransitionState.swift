import AppKit
import ObjectiveC.runtime

enum NativeFullscreenTransitionPhase: String {
    case none
    case entering
    case exiting

    var isTransitioning: Bool {
        self != .none
    }
}

private var yenNativeFullscreenTransitionPhaseKey: UInt8 = 0
#if DEBUG
private var yenTestingSettledFullscreenKey: UInt8 = 0
#endif

extension NSWindow {
    var yenNativeFullscreenTransitionPhase: NativeFullscreenTransitionPhase {
        get {
            guard
                let rawValue = objc_getAssociatedObject(
                    self,
                    &yenNativeFullscreenTransitionPhaseKey
                ) as? NSString,
                let phase = NativeFullscreenTransitionPhase(rawValue: rawValue as String)
            else {
                return .none
            }

            return phase
        }
        set {
            let oldValue = yenNativeFullscreenTransitionPhase
            guard oldValue != newValue else { return }

            objc_setAssociatedObject(
                self,
                &yenNativeFullscreenTransitionPhaseKey,
                newValue.rawValue as NSString,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )

            NotificationCenter.default.post(
                name: .yenNativeFullscreenTransitionDidChange,
                object: self
            )
        }
    }

    var yenIsNativeFullscreenTransitioning: Bool {
        yenNativeFullscreenTransitionPhase.isTransitioning
    }

    var yenIsEffectivelyFullscreen: Bool {
#if DEBUG
        if yenTestingSettledFullscreen {
            return true
        }
#endif
        return styleMask.contains(.fullScreen) || yenIsNativeFullscreenTransitioning
    }
}

#if DEBUG
extension NSWindow {
    /// Tests model settled fullscreen with an associated flag because AppKit rejects
    /// direct `.fullScreen` style-mask mutation outside a real transition.
    var yenTestingSettledFullscreen: Bool {
        get {
            (objc_getAssociatedObject(self, &yenTestingSettledFullscreenKey) as? NSNumber)?.boolValue ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &yenTestingSettledFullscreenKey,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}
#endif

extension Notification.Name {
    static let yenNativeFullscreenTransitionDidChange = Notification.Name(
        "com.yenchat.yen.nativeFullscreenTransitionDidChange"
    )
}
