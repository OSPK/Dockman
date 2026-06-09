import Foundation

/// Parser for the `dockman://` scripting scheme (docs/01 §4.6).
/// Examples:
///   dockman://toggle?dock=Dev
///   dockman://pin?dock=Dev
///   dockman://show?dock=Dev   dockman://hide?dock=Dev
public enum DockmanURL {
    public enum Command: Equatable {
        case toggle(dock: String)
        case pin(dock: String)
        case show(dock: String)
        case hide(dock: String)
    }

    public static func parse(_ url: URL) -> Command? {
        guard url.scheme == "dockman",
              let host = url.host?.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let dock = components.queryItems?.first(where: { $0.name == "dock" })?.value
        guard let dock, !dock.isEmpty else { return nil }
        switch host {
        case "toggle": return .toggle(dock: dock)
        case "pin":    return .pin(dock: dock)
        case "show":   return .show(dock: dock)
        case "hide":   return .hide(dock: dock)
        default:       return nil
        }
    }
}
