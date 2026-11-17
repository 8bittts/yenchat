enum YENIntentError: Error, CustomLocalizedStringResourceConvertible {
    case appUnavailable
    case surfaceNotFound
    case permissionDenied
    case actionNotAllowed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appUnavailable: "The YEN app isn't properly initialized."
        case .surfaceNotFound: "The terminal no longer exists."
        case .permissionDenied: "YEN doesn't allow Shortcuts."
        case .actionNotAllowed: "This Shortcut action is not allowlisted in YEN."
        }
    }
}
