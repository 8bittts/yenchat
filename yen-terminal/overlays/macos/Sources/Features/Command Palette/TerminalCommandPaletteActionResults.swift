import Foundation

enum TerminalCommandPaletteActionResults {
    static func actionResults(
        query: String,
        context: TerminalCommandPaletteContext,
        actions: [TerminalCommandPaletteActionSearchDescriptor]
    ) -> [TerminalCommandPaletteSearchResult] {
        var results: [TerminalCommandPaletteSearchResult] = []
        results.reserveCapacity(actions.count)

        for action in actions {
            if Task.isCancelled {
                break
            }

            let bestMatch = [
                TerminalCommandPaletteSearchEngine.matchScore(query: query, text: action.title),
                TerminalCommandPaletteSearchEngine.matchScore(query: query, text: action.subtitle ?? ""),
                TerminalCommandPaletteSearchEngine.matchScore(query: query, text: action.description ?? ""),
                action.searchTags.map { TerminalCommandPaletteSearchEngine.matchScore(query: query, text: $0) }.max() ?? 0,
            ].max() ?? 0

            guard bestMatch > 0 else { continue }

            let contextBonus = action.searchTags.contains(where: context.contextTags.contains) ? 15 : 0
            let preview = action.subtitle ?? action.description ?? "tags=\(action.searchTags.joined(separator: ","))"
            results.append(
                TerminalCommandPaletteSearchResult(
                source: .action,
                score: TerminalCommandPaletteResultSource.action.weight + bestMatch + contextBonus,
                targetKey: action.orderKey ?? action.title,
                previewKey: preview,
                title: action.title,
                subtitle: action.subtitle ?? action.description,
                execution: .action(id: action.id)
                )
            )
        }

        return results
    }

}
