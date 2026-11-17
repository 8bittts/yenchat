#if os(macOS)

extension AppDelegate {
    /// Show onboarding panel on first launch to guide users through
    /// granting the three permissions required for speech-to-text dictation.
    func showOnboardingIfNeeded() {
        Task { @MainActor in
            guard !isRunningUnderXCTest() else { return }
            guard OnboardingController.needsOnboarding else { return }
            OnboardingController.shared.show()
        }
    }
}

#endif // os(macOS)
