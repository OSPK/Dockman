import Foundation

/// Composite key identifying a Space across sessions (docs/02 §5). Resolved in
/// order uuid → id → ordinal so a binding survives Space-ID churn.
public struct SpaceRef: Codable, Equatable, Sendable {
    public var spaceUUID: String?
    public var spaceID: UInt64?
    public var displayUUID: String?
    public var ordinalIndex: Int?

    public init(spaceUUID: String? = nil, spaceID: UInt64? = nil,
                displayUUID: String? = nil, ordinalIndex: Int? = nil) {
        self.spaceUUID = spaceUUID
        self.spaceID = spaceID
        self.displayUUID = displayUUID
        self.ordinalIndex = ordinalIndex
    }
}

/// Where a Dock appears.
public struct Binding: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case spaces      // pinned to specific Space(s)
        case allSpaces   // visible on every desktop (public canJoinAllSpaces path)
    }
    public var mode: Mode
    public var spaces: [SpaceRef]      // used when mode == .spaces
    public var displayUUIDs: [String]  // empty == all displays

    public init(mode: Mode = .spaces, spaces: [SpaceRef] = [], displayUUIDs: [String] = []) {
        self.mode = mode
        self.spaces = spaces
        self.displayUUIDs = displayUUIDs
    }

    public static let allSpaces = Binding(mode: .allSpaces)
}

/// Visual configuration of a Dock.
public struct Appearance: Codable, Equatable, Sendable {
    public enum Edge: String, Codable, Sendable {
        case bottom, top, left, right
        /// Left/right docks lay their items out vertically.
        public var isVertical: Bool { self == .left || self == .right }
    }
    /// Background treatment (docs/04 §3.1).
    public enum Style: String, Codable, Sendable {
        case liquidGlass   // macOS 26 NSGlassEffectView (falls back to classic)
        case classic       // frosted NSVisualEffectView
        case solid         // opaque tinted slab
        case minimal       // no background slab, icons only

        public var displayName: String {
            switch self {
            case .liquidGlass: return "Liquid Glass"
            case .classic:     return "Classic"
            case .solid:       return "Solid"
            case .minimal:     return "Minimal"
            }
        }
    }
    public var edge: Edge
    public var iconSize: Double
    public var style: Style
    public var tintHex: String?
    /// When true, icons grow with cursor distance (classic Dock magnification),
    /// popping above the bar. Off by default.
    public var magnification: Bool
    /// Inner margin between the icons and the bar's slab edge, in points.
    public var padding: Double
    /// Gap between the bar and its screen edge, in points (0 = flush).
    public var edgeGap: Double

    public static let defaultPadding: Double = 10
    public static let defaultEdgeGap: Double = 16

    public init(edge: Edge = .bottom, iconSize: Double = 52, style: Style = .classic,
                tintHex: String? = nil, magnification: Bool = false,
                padding: Double = Appearance.defaultPadding,
                edgeGap: Double = Appearance.defaultEdgeGap) {
        self.edge = edge
        self.iconSize = iconSize
        self.style = style
        self.tintHex = tintHex
        self.magnification = magnification
        self.padding = padding
        self.edgeGap = edgeGap
    }

    private enum CodingKeys: String, CodingKey {
        case edge, iconSize, style, tintHex, magnification, padding, edgeGap
    }

    // Tolerant decode so configs written before newer fields existed keep the rest.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        edge = try c.decodeIfPresent(Edge.self, forKey: .edge) ?? .bottom
        iconSize = try c.decodeIfPresent(Double.self, forKey: .iconSize) ?? 52
        style = try c.decodeIfPresent(Style.self, forKey: .style) ?? .classic
        tintHex = try c.decodeIfPresent(String.self, forKey: .tintHex)
        magnification = try c.decodeIfPresent(Bool.self, forKey: .magnification) ?? false
        padding = try c.decodeIfPresent(Double.self, forKey: .padding) ?? Appearance.defaultPadding
        edgeGap = try c.decodeIfPresent(Double.self, forKey: .edgeGap) ?? Appearance.defaultEdgeGap
    }
}

public enum FolderStyle: String, Codable, Sendable, Equatable { case grid, list }

/// A scriptable action a Dock item can perform.
public struct DockAction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case openURL     // open a URL / deep link via the system
        case command     // a dockman:// command string handled internally
    }
    public var kind: Kind
    public var value: String
    public var label: String?
    public var symbol: String?   // SF Symbol name for the icon

    public init(kind: Kind, value: String, label: String? = nil, symbol: String? = nil) {
        self.kind = kind
        self.value = value
        self.label = label
        self.symbol = symbol
    }
}

/// A single Dock entry.
public enum DockItem: Codable, Equatable, Sendable {
    case app(bundlePath: String, label: String?)
    case file(path: String, label: String?)
    case folder(path: String, label: String?, style: FolderStyle)
    case spacer(points: Double)
    case separator
    case action(DockAction)
    case runningAppsZone

    public var appPath: String? {
        if case let .app(path, _) = self { return path }
        return nil
    }
    /// Filesystem path for app/file/folder items.
    public var path: String? {
        switch self {
        case .app(let p, _), .file(let p, _): return p
        case .folder(let p, _, _): return p
        default: return nil
        }
    }
    public var label: String? {
        switch self {
        case .app(_, let l), .file(_, let l): return l
        case .folder(_, let l, _): return l
        case .action(let a): return a.label
        default: return nil
        }
    }
    /// Items the user can drag/reorder/remove (everything except the dynamic zone).
    public var isUserManaged: Bool {
        if case .runningAppsZone = self { return false }
        return true
    }
}

/// Behavioral options for a Dock (docs/04 §4.5).
public struct Behavior: Codable, Equatable, Sendable {
    /// Show the Dock even on native-fullscreen Spaces (default: hide there).
    public var showOverFullscreen: Bool
    /// Hide the Dock off the screen edge until the cursor approaches it.
    public var autoHide: Bool
    /// When an app is clicked, move its window onto this Dock's screen (needs Accessibility).
    public var summonWindows: Bool

    public init(showOverFullscreen: Bool = false, autoHide: Bool = false, summonWindows: Bool = false) {
        self.showOverFullscreen = showOverFullscreen
        self.autoHide = autoHide
        self.summonWindows = summonWindows
    }

    private enum CodingKeys: String, CodingKey { case showOverFullscreen, autoHide, summonWindows }

    // Tolerant decode so older configs (without newer fields) still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showOverFullscreen = try c.decodeIfPresent(Bool.self, forKey: .showOverFullscreen) ?? false
        autoHide = try c.decodeIfPresent(Bool.self, forKey: .autoHide) ?? false
        summonWindows = try c.decodeIfPresent(Bool.self, forKey: .summonWindows) ?? false
    }
}

/// A Dock: its items, where it appears, how it looks, how it behaves.
public struct DockModel: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var items: [DockItem]
    public var binding: Binding
    public var appearance: Appearance
    public var behavior: Behavior
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String, items: [DockItem],
                binding: Binding, appearance: Appearance = Appearance(),
                behavior: Behavior = Behavior(), enabled: Bool = true) {
        self.id = id
        self.name = name
        self.items = items
        self.binding = binding
        self.appearance = appearance
        self.behavior = behavior
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, items, binding, appearance, behavior, enabled
    }

    // Tolerant decoding so configs written by older schema versions (no `behavior`,
    // etc.) still load with sensible defaults (docs/03 §6, forward migration).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        items = try c.decode([DockItem].self, forKey: .items)
        binding = try c.decode(Binding.self, forKey: .binding)
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? Appearance()
        behavior = try c.decodeIfPresent(Behavior.self, forKey: .behavior) ?? Behavior()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

public struct GlobalSettings: Codable, Equatable, Sendable {
    public var launchAtLogin: Bool
    public var hideSystemDock: Bool
    /// The system Dock's `autohide` value before we hid it, so we can restore exactly.
    public var priorDockAutohide: Bool?

    public init(launchAtLogin: Bool = false, hideSystemDock: Bool = false, priorDockAutohide: Bool? = nil) {
        self.launchAtLogin = launchAtLogin
        self.hideSystemDock = hideSystemDock
        self.priorDockAutohide = priorDockAutohide
    }

    private enum CodingKeys: String, CodingKey { case launchAtLogin, hideSystemDock, priorDockAutohide }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        hideSystemDock = try c.decodeIfPresent(Bool.self, forKey: .hideSystemDock) ?? false
        priorDockAutohide = try c.decodeIfPresent(Bool.self, forKey: .priorDockAutohide)
    }
}

/// The persisted document.
public struct Config: Codable, Equatable, Sendable {
    /// Bump when the on-disk shape changes; `ConfigStore` migrates forward.
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var docks: [DockModel]
    public var global: GlobalSettings

    public init(schemaVersion: Int = Config.currentSchemaVersion,
                docks: [DockModel] = [], global: GlobalSettings = GlobalSettings()) {
        self.schemaVersion = schemaVersion
        self.docks = docks
        self.global = global
    }

    public static let empty = Config()
}
