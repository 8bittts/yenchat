import AppKit
import AppIntents

/// App intent that retrieves details about a specific terminal.
@available(macOS 14.0, *)
struct GetTerminalDetailsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Details of Terminal"

    @Parameter(
        title: "Detail",
        description: "The detail to extract about a terminal."
    )
    var detail: TerminalDetail

    @Parameter(
        title: "Terminal",
        description: "The terminal to extract information about."
    )
    var terminal: TerminalEntity

    static var supportedModes: IntentModes = .background

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$detail) from \(\.$terminal)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        guard await requestIntentPermission(scope: .read) else {
            throw YENIntentError.permissionDenied
        }

        switch detail {
        case .title: return .result(value: terminal.title)
        case .workingDirectory: return .result(value: terminal.workingDirectory)
        case .allContents:
            let view = try terminal.requireSurfaceView()
            return .result(value: view.cachedScreenContents.get())
        case .selectedText:
            let view = try terminal.requireSurfaceView()
            return .result(value: view.accessibilitySelectedText())
        case .visibleText:
            let view = try terminal.requireSurfaceView()
            return .result(value: view.cachedVisibleContents.get())
        }
    }
}

// MARK: TerminalDetail

enum TerminalDetail: String {
    case title
    case workingDirectory
    case allContents
    case selectedText
    case visibleText
}

extension TerminalDetail: AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Terminal Detail")

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .title: .init(title: "Title"),
        .workingDirectory: .init(title: "Working Directory"),
        .allContents: .init(title: "Full Contents"),
        .selectedText: .init(title: "Selected Text"),
        .visibleText: .init(title: "Visible Text"),
    ]
}

@available(macOS 14.0, *)
private extension TerminalEntity {
    /// Binds the entity's surface view or throws the standard not-found intent error.
    @MainActor
    func requireSurfaceView() throws -> YEN.SurfaceView {
        guard let view = surfaceView else { throw YENIntentError.surfaceNotFound }
        return view
    }
}
