#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Glass

/// Liquid Glass for a floating Settings panel.
///
/// The system material is used as it ships: no tint, no custom background.
/// Before macOS 26 the panel falls back to a standard material with a hairline.
private struct SettingsGlassModifier<GlassShape: InsettableShape>: ViewModifier {
    let shape: GlassShape

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5))
        }
    }
}

extension View {
    /// Glass in any shape: the caption pill uses a capsule.
    func settingsGlass<GlassShape: InsettableShape>(in shape: GlassShape) -> some View {
        modifier(SettingsGlassModifier(shape: shape))
    }

    /// A floating glass panel: the inspector and the theme dock.
    func settingsGlassPanel(cornerRadius: CGFloat = SettingsCornerRadius.glassPanel) -> some View {
        settingsGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Theme Colors

/// The colors the preview and the dock draw for one theme.
struct SettingsStudioTheme: Equatable {
    let name: String
    let isLight: Bool
    let background: Color
    let foreground: Color
    let cursor: Color
    /// ANSI colors 1 through 6: red, green, yellow, blue, magenta, cyan.
    let palette: [Color]

    static let fallback = SettingsStudioTheme(
        name: "YEN",
        isLight: false,
        background: Color(red: 0.149, green: 0.169, blue: 0.212),
        foreground: .white,
        cursor: Color.yenBrand,
        palette: SettingsStudioPalette.fallback
    )

    init(name: String, isLight: Bool, background: Color, foreground: Color, cursor: Color, palette: [Color]) {
        self.name = name
        self.isLight = isLight
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.palette = palette
    }

    init(theme: ThemeInfo) {
        self.init(
            name: theme.displayName,
            isLight: theme.tags.contains("light"),
            background: theme.backgroundColor,
            foreground: theme.foregroundColor,
            cursor: theme.cursorColor,
            palette: SettingsStudioPalette.colors(forThemeAt: theme.path)
        )
    }

    /// The catalog theme the config selects, or the default look when the
    /// catalog has not loaded or the selection is not in it.
    static func resolve(selectedTheme: String, in themes: [ThemeInfo]) -> SettingsStudioTheme {
        guard let match = themes.first(where: {
            SettingsController.themeSelectionMatches(selectedTheme: selectedTheme, catalogThemeName: $0.name)
        }) else {
            return .fallback
        }
        return SettingsStudioTheme(theme: match)
    }
}

/// Reads the six ANSI accent colors from a theme file, cached per path.
enum SettingsStudioPalette {
    static let fallback: [Color] = [
        Color(red: 0.878, green: 0.424, blue: 0.459),
        Color(red: 0.596, green: 0.765, blue: 0.475),
        Color(red: 0.898, green: 0.753, blue: 0.482),
        Color(red: 0.380, green: 0.686, blue: 0.937),
        Color(red: 0.776, green: 0.471, blue: 0.867),
        Color(red: 0.337, green: 0.714, blue: 0.761),
    ]

    private static let lock = NSLock()
    private static var cache: [String: [Color]] = [:]

    static func colors(forThemeAt path: String) -> [Color] {
        lock.lock()
        if let cached = cache[path] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let parsed = parse(contents: (try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
        lock.lock()
        cache[path] = parsed
        lock.unlock()
        return parsed
    }

    /// Parses `palette = N=#rrggbb` lines for N in 1...6. A missing or malformed
    /// entry keeps the fallback color at that position.
    static func parse(contents: String) -> [Color] {
        var colors = fallback
        for line in contents.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 2).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 3, parts[0] == "palette", let index = Int(parts[1]), (1...6).contains(index),
                  let color = Color(hex: parts[2]) else { continue }
            colors[index - 1] = color
        }
        return colors
    }
}

// MARK: - Live Preview

/// The content layer of the Settings window: a terminal that shows the current
/// theme, font, cursor, padding, opacity, background image and border.
struct SettingsStudioPreview: View {
    let appearance: GeneralSettingsStore.Snapshot.Appearance
    let font: GeneralSettingsStore.Snapshot.Font
    let cursor: GeneralSettingsStore.Snapshot.Cursor
    let theme: SettingsStudioTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    private var textFont: Font {
        .custom(font.fontFamily, size: font.fontSize)
    }

    private func line(_ segments: [(String, Color)]) -> Text {
        segments.reduce(Text("")) { partial, segment in
            partial + Text(segment.0).foregroundColor(segment.1)
        }
    }

    private var prompt: [(String, Color)] {
        [("~/code/yen", theme.palette[3]), (" main", theme.palette[4]), (" ❯ ", theme.palette[1])]
    }

    private var lines: [Text] {
        let dim = theme.foreground.opacity(0.6)
        return [
            line(prompt + [("git status --short", theme.foreground)]),
            line([(" M", theme.palette[2]), (" Sources/Settings/Appearance.swift", theme.foreground)]),
            line([(" A", theme.palette[1]), (" Sources/Settings/ThemeDock.swift", theme.foreground)]),
            line(prompt + [("swift build", theme.foreground), (" -c release", dim)]),
            line([("Compiling", theme.palette[5]), (" YEN", theme.foreground), (" (42 sources)", dim)]),
            line([("Build complete!", theme.palette[1]), (" (3.41s)", dim)]),
            line(prompt + [("yen", theme.palette[0]), (" theme", theme.foreground), (" --list", theme.palette[2])]),
        ]
    }

    @ViewBuilder
    private var cursorShape: some View {
        let width = max(font.fontSize * 0.6, 4)
        let height = font.fontSize * 1.2
        switch cursor.cursorStyle {
        case "bar":
            Rectangle().fill(theme.cursor).frame(width: 2, height: height)
        case "underline":
            Rectangle().fill(theme.cursor).frame(width: width, height: 2)
                .frame(height: height, alignment: .bottom)
        default:
            Rectangle().fill(theme.cursor).frame(width: width, height: height)
        }
    }

    @ViewBuilder
    private var cursorView: some View {
        if cursor.cursorBlink && !reduceMotion {
            TimelineView(.periodic(from: .now, by: 0.6)) { context in
                cursorShape.opacity(Int(context.date.timeIntervalSinceReferenceDate / 0.6) % 2 == 0 ? 1 : 0)
            }
        } else {
            cursorShape
        }
    }

    var body: some View {
        let padding = CGFloat(appearance.windowPaddingX)
        ZStack(alignment: .topLeading) {
            theme.background.opacity(appearance.backgroundOpacity)

            if let image = appearance.backgroundImagePreview.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            }

            VStack(alignment: .leading, spacing: font.fontSize * 0.28) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, text in
                    text
                }
                HStack(spacing: 0) {
                    line(prompt)
                    cursorView
                }
            }
            .font(textFont)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.top, SettingsSpacing.previewTopInset + CGFloat(appearance.windowPaddingY))
            .padding(.leading, SettingsSpacing.previewLeadingInset + padding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .overlay {
            if appearance.windowBorderEnabled {
                // The same stroke metrics a terminal window uses, so the weight
                // and the corner shown here are the ones the user gets.
                let stroke = WindowBorderRenderingPolicy.strokeModel(
                    width: appearance.windowBorderWidth,
                    radius: appearance.windowBorderRadius,
                    chromeMode: .native,
                    isFocused: true,
                    useDashedUnfocusedStyle: false
                )
                RoundedRectangle(cornerRadius: stroke.cornerRadius, style: .continuous)
                    .inset(by: stroke.inset)
                    .stroke(
                        LinearGradient(
                            colors: [
                                appearance.windowBorderFocusedGradient.startColor,
                                appearance.windowBorderFocusedGradient.endColor,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: stroke.lineWidth
                    )
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Terminal preview")
        .accessibilityValue("\(theme.name) theme, \(font.fontFamily) \(Int(font.fontSize)) point")
    }
}

// MARK: - Theme Dock

/// The floating glass dock: every theme in the catalog as a swatch.
struct SettingsStudioThemeDock: View {
    @ObservedObject var store: ThemesSettingsStore

    /// Ten swatches a row: the 20-theme catalog fills two rows.
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: SettingsSpacing.swatchSpacing),
        count: 10
    )

    private func isSelected(_ theme: ThemeInfo) -> Bool {
        SettingsController.themeSelectionMatches(
            selectedTheme: store.snapshot.selectedTheme,
            catalogThemeName: theme.name
        )
    }

    var body: some View {
        let themes = store.snapshot.themes
        let current = SettingsStudioTheme.resolve(selectedTheme: store.snapshot.selectedTheme, in: themes)

        VStack(alignment: .leading, spacing: SettingsSpacing.dockHeaderSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: SettingsSpacing.controlSpacing) {
                Text(current.name)
                    .fontWeight(.semibold)
                Text(current.isLight ? "Light" : "Dark")
                    .foregroundStyle(.secondary)
                Text("· \(themes.count) themes")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if store.snapshot.isThemeCatalogLoading {
                    ProgressView().controlSize(.small)
                }
            }
            .font(SettingsTypography.dockTitle)

            if themes.isEmpty {
                Text(store.snapshot.isThemeCatalogLoading ? "Loading themes…" : "No themes found.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: SettingsSpacing.swatchSpacing) {
                    ForEach(themes, id: \.name) { theme in
                        SettingsStudioThemeSwatch(
                            theme: theme,
                            isSelected: isSelected(theme),
                            action: { store.applyTheme(theme) }
                        )
                    }
                }
            }
        }
        .padding(SettingsSpacing.dockPadding)
        .settingsGlassPanel()
    }
}

private struct SettingsStudioThemeSwatch: View {
    let theme: ThemeInfo
    let isSelected: Bool
    let action: () -> Void

    // The swatch is a miniature of the terminal: five accent dots in the
    // bottom-leading corner of the theme's background.
    private static let dotSize: CGFloat = 5
    private static let dotSpacing: CGFloat = 3
    private static let dotInset = CGSize(width: 7, height: 6)
    private static let aspectRatio: CGFloat = 16.0 / 11.0
    private static let selectionWidth: CGFloat = 2.5

    var body: some View {
        let palette = SettingsStudioPalette.colors(forThemeAt: theme.path)
        let shape = RoundedRectangle(cornerRadius: SettingsCornerRadius.prominent, style: .continuous)

        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                shape.fill(theme.backgroundColor)
                HStack(spacing: Self.dotSpacing) {
                    ForEach(0..<5, id: \.self) { index in
                        Circle().fill(palette[index]).frame(width: Self.dotSize, height: Self.dotSize)
                    }
                }
                .padding(.leading, Self.dotInset.width)
                .padding(.bottom, Self.dotInset.height)
            }
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
            .overlay(
                shape
                    .inset(by: -Self.selectionWidth)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: Self.selectionWidth)
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(theme.displayName)
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#endif // os(macOS)
