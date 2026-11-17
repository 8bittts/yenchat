// YEN Overlay: replaces upstream macos/Sources/Features/Command Palette/CommandPalette.swift
//
// Divergence from upstream:
//   - stable CommandOption IDs so provider-backed result sets do not thrash row identity
//   - optional external query/results hooks so overlays can augment the palette without
//     pushing YEN-specific search logic into vendor-owned code
//   - configurable empty-state copy for async provider search
//
// Upstream structure preserved: palette query field, keyboard handling, command table,
// and row rendering remain generic UI concerns.
// Merge strategy on a vendor bump: diff upstream CommandPalette.swift, merge shell/row updates
// into preserved sections while keeping the overlay hook surface minimal and generic.

import AppKit
import SwiftUI

struct CommandOption: Identifiable, Hashable {
    /// Stable identifier for this option.
    let id: String
    /// The primary text displayed for this command.
    let title: String
    /// Secondary text displayed below the title.
    let subtitle: String?
    /// Tooltip text shown on hover.
    let description: String?
    /// Keyboard shortcut symbols to display.
    let symbols: [String]?
    /// SF Symbol name for the leading icon.
    let leadingIcon: String?
    /// Color for the leading indicator circle.
    let leadingColor: Color?
    /// Badge text displayed as a pill.
    let badge: String?
    /// Whether to visually emphasize this option.
    let emphasis: Bool
    /// Sort key for stable ordering when titles are equal.
    /// Upstream 5c952ac/#13872 narrowed this from AnySortKey to ObjectIdentifier.
    let sortKey: ObjectIdentifier?
    /// The action to perform when this option is selected.
    let action: () -> Void

    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String? = nil,
        description: String? = nil,
        symbols: [String]? = nil,
        leadingIcon: String? = nil,
        leadingColor: Color? = nil,
        badge: String? = nil,
        emphasis: Bool = false,
        sortKey: ObjectIdentifier? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.symbols = symbols
        self.leadingIcon = leadingIcon
        self.leadingColor = leadingColor
        self.badge = badge
        self.emphasis = emphasis
        self.sortKey = sortKey
        self.action = action
    }

    static func == (lhs: CommandOption, rhs: CommandOption) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    var backgroundColor: Color = Color(nsColor: .windowBackgroundColor)
    var options: [CommandOption]
    var externalQuery: Binding<String>? = nil
    var displayedOptions: [CommandOption]? = nil
    var emptyStateText: String = "No matches"
    var onQueryChange: ((String) -> Void)? = nil
    var onWillSelectOption: ((CommandOption) -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    @State private var query = ""
    @State private var selectedIndex: UInt?
    @State private var hoveredOptionID: String?
    @FocusState private var isTextFieldFocused: Bool

    private var queryBinding: Binding<String> {
        externalQuery ?? $query
    }

    private var currentQuery: String {
        externalQuery?.wrappedValue ?? query
    }

    private var filteredOptionIDs: [String] {
        filteredOptions.map(\.id)
    }

    static func filteredOptionsForTesting(
        options: [CommandOption],
        displayedOptions: [CommandOption]? = nil
    ) -> [CommandOption] {
        resolveFilteredOptions(
            options: options,
            displayedOptions: displayedOptions
        )
    }

    nonisolated static func shouldDismissForKeyDown(keyCode: UInt16) -> Bool {
        keyCode == 0x35 // Escape
    }

    nonisolated static func shouldDismissForMouseDown(
        eventType: NSEvent.EventType,
        eventWindowMatchesPalette: Bool,
        locationInPalette: NSPoint?,
        paletteBounds: NSRect
    ) -> Bool {
        switch eventType {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard eventWindowMatchesPalette, let locationInPalette else { return true }
            return !paletteBounds.contains(locationInPalette)
        default:
            return false
        }
    }

    // The options to show: the externally-supplied displayedOptions when present
    // (already filtered upstream), otherwise the unfiltered options.
    var filteredOptions: [CommandOption] {
        Self.resolveFilteredOptions(
            options: options,
            displayedOptions: displayedOptions
        )
    }

    var selectedOption: CommandOption? {
        guard let selectedIndex else { return nil }
        return if selectedIndex < filteredOptions.count {
            filteredOptions[Int(selectedIndex)]
        } else {
            filteredOptions.last
        }
    }

    private func dismiss() {
        guard isPresented else { return }
        onDismiss?()
        isPresented = false
    }

    var body: some View {
        let scheme: ColorScheme = if NSColor(backgroundColor).isLightColor {
            .light
        } else {
            .dark
        }

        VStack(alignment: .leading, spacing: 0) {
            CommandPaletteQuery(query: queryBinding, isTextFieldFocused: _isTextFieldFocused) { event in
                switch event {
                case .exit:
                    dismiss()

                case .submit:
                    guard let selectedOption else {
                        dismiss()
                        break
                    }

                    onWillSelectOption?(selectedOption)
                    dismiss()
                    selectedOption.action()

                case .move(.up):
                    if filteredOptions.isEmpty { break }
                    let current = selectedIndex ?? UInt(filteredOptions.count)
                    selectedIndex = (current == 0)
                        ? UInt(filteredOptions.count - 1)
                        : current - 1

                case .move(.down):
                    if filteredOptions.isEmpty { break }
                    let current = selectedIndex ?? UInt.max
                    selectedIndex = (current >= UInt(filteredOptions.count - 1))
                        ? 0
                        : current + 1

                case .move:
                    break
                }
            }
            .onChange(of: currentQuery) { newValue in
                onQueryChange?(newValue)
                if !newValue.isEmpty {
                    if selectedIndex == nil {
                        selectedIndex = 0
                    }
                } else if let selectedIndex, selectedIndex == 0 {
                    self.selectedIndex = nil
                }
            }

            Divider()

            CommandTable(
                options: filteredOptions,
                emptyStateText: emptyStateText,
                selectedIndex: $selectedIndex,
                hoveredOptionID: $hoveredOptionID
            ) { option in
                onWillSelectOption?(option)
                dismiss()
                option.action()
            }
        }
        .frame(maxWidth: 500)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(backgroundColor)
                    .blendMode(.color)
            }
                .compositingGroup()
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .tertiaryLabelColor).opacity(0.75))
        )
        .background(
            CommandPaletteDismissalMonitor(
                isPresented: $isPresented,
                onDismiss: onDismiss
            )
        )
        .shadow(radius: 32, x: 0, y: 12)
        .padding()
        .environment(\.colorScheme, scheme)
        .onChange(of: filteredOptionIDs) { _ in
            guard let selectedIndex else { return }
            if filteredOptions.isEmpty {
                self.selectedIndex = nil
            } else if selectedIndex >= filteredOptions.count {
                self.selectedIndex = UInt(filteredOptions.count - 1)
            }
        }
        .onChange(of: isPresented) { newValue in
            isTextFieldFocused = newValue
            if !isPresented {
                queryBinding.wrappedValue = ""
            }
        }
        .onAppear {
            // FocusState updates issued while the overlay is still joining the responder
            // chain can be dropped. Defer one main-loop turn so the query field exists in
            // the key window before requesting focus.
            DispatchQueue.main.async {
                guard isPresented else { return }
                isTextFieldFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            dismiss()
        }
    }

    /// Production always supplies `displayedOptions` (already filtered upstream by the query in
    /// TerminalCommandPalette), so return those when present and otherwise fall back to the
    /// unfiltered options. The old client-side scoring path for nil displayedOptions was
    /// unreachable in production and has been removed.
    private static func resolveFilteredOptions(
        options: [CommandOption],
        displayedOptions: [CommandOption]?
    ) -> [CommandOption] {
        displayedOptions ?? options
    }
}

private struct CommandPaletteDismissalMonitor: NSViewRepresentable {
    @Binding var isPresented: Bool
    var onDismiss: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setAccessibilityElement(false)
        context.coordinator.start(monitoring: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isPresented = $isPresented
        context.coordinator.onDismiss = onDismiss
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        weak var paletteView: NSView?
        var isPresented: Binding<Bool>?
        var onDismiss: (() -> Void)?
        private var eventMonitor: Any?

        func start(monitoring view: NSView) {
            stop()
            paletteView = view
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func stop() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isPresented?.wrappedValue == true,
                  let paletteView,
                  let window = paletteView.window else {
                return event
            }

            if event.window === window,
               event.type == .keyDown,
               CommandPaletteView.shouldDismissForKeyDown(keyCode: event.keyCode) {
                dismiss()
                return nil
            }

            let eventWindowMatchesPalette = event.window === window
            let locationInPalette = eventWindowMatchesPalette
                ? paletteView.convert(event.locationInWindow, from: nil)
                : nil
            if CommandPaletteView.shouldDismissForMouseDown(
                eventType: event.type,
                eventWindowMatchesPalette: eventWindowMatchesPalette,
                locationInPalette: locationInPalette,
                paletteBounds: paletteView.bounds
            ) {
                dismiss()
            }

            return event
        }

        private func dismiss() {
            guard isPresented?.wrappedValue == true else { return }
            onDismiss?()
            isPresented?.wrappedValue = false
        }
    }
}

/// The text field for building the query for the command palette.
private struct CommandPaletteQuery: View {
    @Binding var query: String
    var onEvent: ((KeyboardEvent) -> Void)?
    @FocusState private var isTextFieldFocused: Bool

    init(query: Binding<String>, isTextFieldFocused: FocusState<Bool>, onEvent: ((KeyboardEvent) -> Void)? = nil) {
        _query = query
        self.onEvent = onEvent
        _isTextFieldFocused = isTextFieldFocused
    }

    enum KeyboardEvent {
        case exit
        case submit
        case move(MoveCommandDirection)
    }

    var body: some View {
        ZStack {
            Group {
                Button { onEvent?(.move(.up)) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button { onEvent?(.move(.down)) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.downArrow, modifiers: [])

                Button { onEvent?(.move(.up)) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.init("p"), modifiers: [.control])
                Button { onEvent?(.move(.down)) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.init("n"), modifiers: [.control])
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)

            TextField("Execute a command…", text: $query)
                .padding()
                .settingsScaledSystemFont(size: 20, relativeTo: .title3, weight: .light)
                .frame(height: 48)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .onChange(of: isTextFieldFocused) { focused in
                    if !focused {
                        onEvent?(.exit)
                    }
                }
                .onExitCommand { onEvent?(.exit) }
                .onMoveCommand { onEvent?(.move($0)) }
                .onSubmit { onEvent?(.submit) }
        }
    }
}

private struct CommandTable: View {
    var options: [CommandOption]
    var emptyStateText: String
    @Binding var selectedIndex: UInt?
    @Binding var hoveredOptionID: String?
    var action: (CommandOption) -> Void

    var body: some View {
        if options.isEmpty {
            Text(emptyStateText)
                .foregroundStyle(.secondary)
                .padding()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(options.enumerated()), id: \.1.id) { index, option in
                            CommandRow(
                                option: option,
                                isSelected: {
                                    if let selected = selectedIndex {
                                        return selected == index ||
                                            (selected >= options.count &&
                                                index == options.count - 1)
                                    } else {
                                        return false
                                    }
                                }(),
                                hoveredID: $hoveredOptionID
                            ) {
                                action(option)
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 200)
                .onChange(of: selectedIndex) { _ in
                    guard let selectedIndex,
                          selectedIndex < options.count else { return }
                    let option = options[Int(selectedIndex)]
                    proxy.scrollTo(option.id)
                    CommandPaletteAccessibility.announceSelection(option.title)
                }
            }
        }
    }
}

/// A single row in the command palette.
private struct CommandRow: View {
    let option: CommandOption
    var isSelected: Bool
    @Binding var hoveredID: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let color = option.leadingColor {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }

                if let icon = option.leadingIcon {
                    Image(systemName: icon)
                        .foregroundStyle(option.emphasis ? Color.accentColor : .secondary)
                        .font(.system(size: 14, weight: .medium))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .fontWeight(option.emphasis ? .medium : .regular)

                    if let subtitle = option.subtitle ?? option.description {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let badge = option.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.accentColor.opacity(0.15))
                        )
                        .foregroundStyle(Color.accentColor)
                }

                if let symbols = option.symbols {
                    ShortcutSymbolsView(symbols: symbols)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .contentShape(Rectangle())
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.2)
                    : (hoveredID == option.id
                       ? Color.secondary.opacity(0.2)
                       : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.accentColor.opacity(option.emphasis && !isSelected ? 0.3 : 0), lineWidth: 1.5)
            )
            .cornerRadius(5)
        }
        .help(option.description ?? "")
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering in
            hoveredID = hovering ? option.id : nil
        }
    }
}

enum CommandPaletteAccessibility {
    static func announceSelection(_ title: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: title,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }
}

/// A row of Text representing a shortcut.
private struct ShortcutSymbolsView: View {
    let symbols: [String]

    var body: some View {
        HStack(spacing: 1) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .frame(minWidth: 13)
            }
        }
    }
}

extension String {
    /// Returns the character indices that match `query`, trying a substring match first,
    /// then falling back to initials matching (first letter of each word).
    /// - Returns: `nil` if neither matches.
    func matchedIndices(for query: String) -> [String.Index]? {
        guard !query.isEmpty else { return nil }

        // Prefer substring match.
        if let range = self.range(of: query, options: .caseInsensitive) {
            return Array(self[range].indices)
        }

        // Fall back to initials match.
        let words = self.split(whereSeparator: \.isWhitespace)
        var queryIndex = query.startIndex
        var matched: [String.Index] = []

        for word in words {
            guard queryIndex < query.endIndex else { break }

            if word.first?.lowercased() == query[queryIndex].lowercased() {
                matched.append(word.startIndex)
                queryIndex = query.index(after: queryIndex)
            }
        }

        return queryIndex == query.endIndex ? matched : nil
    }
}

// MARK: - Match score

// YEN filters and ranks palette options through TerminalCommandPaletteSearch, so
// this upstream matcher is not on YEN's presentation path. It is retained
// verbatim because it is part of the Ghostty module's public surface and backs
// upstream's CommandPaletteTests; dropping it breaks the test target build.

extension Collection where Element == CommandOption {
    /// Filters to the options matching `query` and ranks them best-first while
    /// maintaining original order: a closer leading color match always wins,
    /// then a title match beats a subtitle match beats a description match.
    func filteredAndSorted(query: String) -> [Element] {
        compactMap { CommandOptionMatch(option: $0, query: query) }
            .sorted {
                ($0.colorScore, $0.textScore) > ($1.colorScore, $1.textScore)
            }
            .map(\.option)
    }
}

/// A scored match of a command option against a palette query.
struct CommandOptionMatch {
    let option: CommandOption
    /// How closely the option's leading color matches a color name in the
    /// query, from 0 (no match) to 1 (exact).
    let colorScore: Double
    /// Which text field matched, ranked: title (3), subtitle (2),
    /// description (1), none (0).
    let textScore: Int

    /// Returns nil if the option doesn't match the query at all.
    init?(option: CommandOption, query: String) {
        let colorScore = Self.colorMatchScore(for: option.leadingColor, query: query)
        let textScore: Int = if option.title.matchedIndices(for: query) != nil {
            3
        } else if option.subtitle?.matchedIndices(for: query) != nil {
            2
        } else if option.description?.matchedIndices(for: query) != nil {
            1
        } else {
            0
        }

        guard colorScore > 0 || textScore > 0 else { return nil }
        self.option = option
        self.colorScore = colorScore
        self.textScore = textScore
    }

    /// Returns a score (0.0 to 1.0) indicating how well a color matches a search query color name.
    /// Returns 0 if no color name in the query matches, or if the color is nil.
    static func colorMatchScore(for color: Color?, query: String) -> Double {
        guard let color = color else { return 0 }

        let queryLower = query.lowercased()
        let nsColor = NSColor(color)

        var bestScore: Double = 0
        for name in NSColor.colorNames {
            guard queryLower.contains(name),
                  let systemColor = NSColor(named: name) else { continue }

            let distance = nsColor.distance(to: systemColor)
            // Max distance in weighted RGB space is ~3.0, so normalize and invert
            // Use a threshold to determine "close enough" matches
            let maxDistance: Double = 1.5
            if distance < maxDistance {
                let score = 1.0 - (distance / maxDistance)
                bestScore = max(bestScore, score)
            }
        }

        return bestScore
    }
}
