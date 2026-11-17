#if os(macOS)
import SwiftUI

/// Frosted glass background for SwiftUI panels hosted in AppKit windows.
/// Used by SettingsPanel, OnboardingPanel, and AboutView.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let isEmphasized: Bool

    init(material: NSVisualEffectView.Material,
         blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
         isEmphasized: Bool = false)
    {
        self.material = material
        self.blendingMode = blendingMode
        self.isEmphasized = isEmphasized
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = isEmphasized
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffect = NSVisualEffectView()
        visualEffect.material = material
        visualEffect.blendingMode = blendingMode
        visualEffect.isEmphasized = isEmphasized
        visualEffect.autoresizingMask = [.width, .height]
        return visualEffect
    }
}
#endif // os(macOS)
