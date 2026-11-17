import AppIntents
import Cocoa

// MARK: AppEntity

@available(macOS 14.0, *)
struct CommandEntity: AppEntity {
    let id: ID

    // Note: for macOS 26 we can move all the properties to @ComputedProperty.

    @Property(title: "Title")
    var title: String

    @Property(title: "Description")
    var description: String

    @Property(title: "Action")
    var action: String

    /// The underlying data model
    let command: YEN.Command

    /// A command identifier is a composite key based on the terminal and canonical action.
    struct ID: Hashable {
        let terminalId: TerminalEntity.ID
        let actionIdentity: String
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Command Palette Command")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: command.title),
            subtitle: LocalizedStringResource(stringLiteral: command.description)
        )
    }

    static var defaultQuery = CommandQuery()

    init(_ command: YEN.Command, for terminal: TerminalEntity) {
        self.id = .init(terminalId: terminal.id, actionIdentity: command.action)
        self.command = command
        self.title = command.title
        self.description = command.description
        self.action = command.action
    }
}

@available(macOS 14.0, *)
extension CommandEntity.ID: RawRepresentable {
    var rawValue: String {
        return "\(terminalId):\(actionIdentity)"
    }

    init?(rawValue: String) {
        let components = rawValue.split(separator: ":", maxSplits: 1)
        guard components.count == 2 else { return nil }

        guard let terminalId = TerminalEntity.ID(uuidString: String(components[0])) else {
            return nil
        }

        self.terminalId = terminalId
        self.actionIdentity = String(components[1])
    }
}

// Required by AppEntity
@available(macOS 14.0, *)
extension CommandEntity.ID: EntityIdentifierConvertible {
    static func entityIdentifier(for entityIdentifierString: String) -> CommandEntity.ID? {
        .init(rawValue: entityIdentifierString)
    }

    var entityIdentifierString: String {
        rawValue
    }
}

// MARK: EntityQuery

@available(macOS 14.0, *)
struct CommandQuery: EntityQuery {
    // Inject terminal parameter from both intents that consume CommandEntity.
    @IntentParameterDependency<CommandPaletteIntent>(\.$terminal)
    var commandPaletteIntent

    @IntentParameterDependency<KeybindIntent>(\.$terminal)
    var keybindIntent

    @MainActor
    func entities(for identifiers: [CommandEntity.ID]) async throws -> [CommandEntity] {
        guard let appDelegate = AppDelegate.shared else { return [] }
        let commands = appDelegate.yen.config.commandPaletteEntries.filter(\.isSupported)

        // Extract unique terminal IDs to avoid fetching duplicates
        let terminalIds = Set(identifiers.map(\.terminalId))
        let terminals = try await TerminalEntity.defaultQuery.entities(for: Array(terminalIds))

        // Build a lookup from terminal ID to terminal entity
        let terminalMap: [TerminalEntity.ID: TerminalEntity] =
            terminals.reduce(into: [:]) { result, terminal in
                result[terminal.id] = terminal
            }

        // Map each identifier to its corresponding CommandEntity. If a command doesn't
        // exist it maps to nil and is removed via compactMap.
        return identifiers.compactMap { id in
            guard let terminal = terminalMap[id.terminalId],
                  let command = resolveAutomationCommandIdentity(
                      id.actionIdentity,
                      commands: commands,
                      allowLegacyActionKeyFallback: true
                  ) else {
                return nil
            }

            return CommandEntity(command, for: terminal)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [CommandEntity] {
        guard let appDelegate = AppDelegate.shared else { return [] }

        let terminal = commandPaletteIntent?.terminal ?? keybindIntent?.terminal
        guard let terminal else { return [] }

        return appDelegate.yen.config.commandPaletteEntries
            .filter(\.isSupported)
            .map {
            CommandEntity($0, for: terminal)
        }
    }
}
