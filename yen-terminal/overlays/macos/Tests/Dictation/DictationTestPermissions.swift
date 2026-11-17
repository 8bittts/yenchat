import AVFoundation
import ApplicationServices
import Foundation

/// Permission preflight shared by the dictation tests.
///
/// Touching `AVAudioEngine.inputNode` triggers a microphone TCC prompt when the
/// grant is absent. That prompt is modal, is attributed to the host app ("A program
/// running within YEN would like to use your microphone"), and blocks the entire
/// test run while stealing focus from anything else in flight — which is how one
/// unguarded audio test can make an unrelated UI suite fail.
///
/// So: never provoke it. Check first, and skip loudly when the grant is missing.
enum DictationTestPermissions {
    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Human-readable permission state, attached to failures so a missing grant is
    /// visible instead of surfacing as a confusing Core Audio error.
    static var summary: String {
        let status: String
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: status = "authorized"
        case .denied: status = "denied"
        case .restricted: status = "restricted"
        case .notDetermined: status = "notDetermined"
        @unknown default: status = "unknown"
        }
        return "microphone=\(status) accessibility=\(AXIsProcessTrusted())"
    }

}
