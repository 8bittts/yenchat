#if os(macOS)
import SwiftUI
import AppKit

/// One segment of a `SettingsSegmentedControl`.
struct SettingsSegment<Value: Hashable> {
    let value: Value
    let title: String
    /// An SF Symbol shown instead of the title. The title stays the segment's
    /// tooltip and its VoiceOver label.
    var symbolName: String?
}

/// A segmented control whose segments share the offered width equally.
///
/// SwiftUI's segmented `Picker` on macOS keeps its natural width: it never
/// stretches to fill a row and never shrinks below its labels. The five
/// shortcut groups measured 395 pt, wider than the inspector, which pushed the
/// whole pane past the panel's right edge. This wraps `NSSegmentedControl` with
/// `.fillEqually` distribution and takes the width it is offered, so the
/// segments spread evenly and the control can never overflow its container.
struct SettingsSegmentedControl<Value: Hashable>: NSViewRepresentable {
    let accessibilityLabel: String
    let segments: [SettingsSegment<Value>]
    @Binding var selection: Value
    var controlSize: NSControl.ControlSize = .regular

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, values: segments.map(\.value))
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.trackingMode = .selectOne
        control.segmentDistribution = .fillEqually
        control.target = context.coordinator
        control.action = #selector(Coordinator.segmentChanged(_:))
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setAccessibilityLabel(accessibilityLabel)
        configure(control)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.values = segments.map(\.value)
        if control.segmentCount != segments.count {
            configure(control)
        }
        control.controlSize = controlSize
        control.selectedSegmentBezelColor = NSColor(Color.accentColor)
        let index = segments.firstIndex { $0.value == selection } ?? -1
        if control.selectedSegment != index {
            control.selectedSegment = index
        }
    }

    /// Takes the offered width and the control's own height.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView control: NSSegmentedControl, context: Context) -> CGSize? {
        let fitting = control.fittingSize
        return CGSize(width: proposal.width ?? fitting.width, height: fitting.height)
    }

    private func configure(_ control: NSSegmentedControl) {
        control.segmentCount = segments.count
        control.controlSize = controlSize
        for (index, segment) in segments.enumerated() {
            if let symbolName = segment.symbolName,
               let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: segment.title) {
                control.setImage(image, forSegment: index)
                control.setLabel("", forSegment: index)
            } else {
                control.setImage(nil, forSegment: index)
                control.setLabel(segment.title, forSegment: index)
            }
            control.setToolTip(segment.title, forSegment: index)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<Value>
        var values: [Value]

        init(selection: Binding<Value>, values: [Value]) {
            self.selection = selection
            self.values = values
        }

        @objc func segmentChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard values.indices.contains(index) else { return }
            selection.wrappedValue = values[index]
        }
    }
}

#endif // os(macOS)
