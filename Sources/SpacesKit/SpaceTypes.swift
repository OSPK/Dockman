import Foundation

/// The kind of a macOS Space, as reported by the WindowServer.
public enum SpaceType: Int, Sendable, Equatable {
    case user = 0          // standard desktop Space
    case fullscreen = 2    // auto-created Space backing a native-fullscreen app
    case system = 4        // legacy/system (e.g. old Dashboard)
    case unknown = -1
}

/// A single Space (virtual desktop).
public struct SpaceInfo: Sendable, Equatable {
    public let id: UInt64        // Managed Space ID (stable within a login session)
    public let uuid: String?     // string UUID (more stable for persistence)
    public let type: SpaceType

    public init(id: UInt64, uuid: String?, type: SpaceType) {
        self.id = id
        self.uuid = uuid
        self.type = type
    }
}

/// One managed display as the WindowServer sees it. With "Displays have separate
/// Spaces" OFF there is a single entry whose `displayIdentifier == "Main"` whose
/// `spaces` span all physical displays. With it ON there is one entry per display.
public struct ManagedDisplay: Sendable, Equatable {
    public let displayIdentifier: String   // a display UUID, or "Main" when DHSS is OFF
    public let currentSpace: SpaceInfo?
    public let spaces: [SpaceInfo]

    public init(displayIdentifier: String, currentSpace: SpaceInfo?, spaces: [SpaceInfo]) {
        self.displayIdentifier = displayIdentifier
        self.currentSpace = currentSpace
        self.spaces = spaces
    }
}

/// A snapshot of the whole Spaces layout plus the detected DHSS topology.
public struct SpacesTopology: Sendable, Equatable {
    public let displays: [ManagedDisplay]
    /// True when "Displays have separate Spaces" is OFF (one Space spans all displays).
    public let spansDisplays: Bool

    public init(displays: [ManagedDisplay], spansDisplays: Bool) {
        self.displays = displays
        self.spansDisplays = spansDisplays
    }

    /// All Spaces across all displays.
    public var allSpaces: [SpaceInfo] { displays.flatMap(\.spaces) }
}

/// Which private capabilities resolved at runtime. Drives graceful degradation
/// (see docs/05 R-1): if `moveWindows`/`addRemoveWindows` are missing we fall
/// back to the public `.canJoinAllSpaces` path.
public struct SpacesCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let readTopology      = SpacesCapabilities(rawValue: 1 << 0)
    public static let readWindowSpaces  = SpacesCapabilities(rawValue: 1 << 1)
    public static let moveWindows       = SpacesCapabilities(rawValue: 1 << 2)
    public static let addRemoveWindows  = SpacesCapabilities(rawValue: 1 << 3)
    public static let spaceType         = SpacesCapabilities(rawValue: 1 << 4)

    /// True when we can hard-pin a window to a specific Space.
    public var canHardPin: Bool { contains(.moveWindows) || contains(.addRemoveWindows) }

    public var description: String {
        var parts: [String] = []
        if contains(.readTopology)     { parts.append("readTopology") }
        if contains(.readWindowSpaces) { parts.append("readWindowSpaces") }
        if contains(.moveWindows)      { parts.append("moveWindows") }
        if contains(.addRemoveWindows) { parts.append("addRemoveWindows") }
        if contains(.spaceType)        { parts.append("spaceType") }
        return parts.isEmpty ? "<none>" : parts.joined(separator: ", ")
    }
}
