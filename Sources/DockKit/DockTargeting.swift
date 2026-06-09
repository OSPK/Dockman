import AppKit
import ConfigKit
import SpacesKit

/// A physical display, enumerated with a stable spatial ordinal (docs/09 §2).
public struct MonitorInfo: Equatable {
    public let uuid: String
    public let ordinal: Int     // 1-based, ordered left→right then top→bottom
    public let name: String
    public let isMain: Bool
    public let frame: NSRect    // global AppKit coordinates (y up)

    public init(uuid: String, ordinal: Int, name: String, isMain: Bool, frame: NSRect) {
        self.uuid = uuid
        self.ordinal = ordinal
        self.name = name
        self.isMain = isMain
        self.frame = frame
    }
}

public enum Monitors {
    /// Current displays with stable spatial ordinals.
    public static func current() -> [MonitorInfo] {
        let mainID = CGMainDisplayID()
        let sorted = NSScreen.screens.sorted { a, b in
            if a.frame.minX != b.frame.minX { return a.frame.minX < b.frame.minX }
            return a.frame.maxY > b.frame.maxY
        }
        var result: [MonitorInfo] = []
        var ordinal = 1
        for screen in sorted {
            guard let uuid = DockController.uuid(for: screen) else { continue }
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            result.append(MonitorInfo(uuid: uuid,
                                      ordinal: ordinal,
                                      name: screen.localizedName,
                                      isMain: displayID == mainID,
                                      frame: screen.frame))
            ordinal += 1
        }
        return result
    }
}

/// Pure mapping from a targeting selection to a persisted `Binding`. Kept free of
/// any view code so it is unit-testable without a GUI (docs/09 §7).
public enum DockTargeting {
    /// - Parameters:
    ///   - allDesktops: user chose "show on all desktops".
    ///   - space: the selected desktop (nil ⇒ none chosen).
    ///   - ordinal: index of `space` within its display's stack (for ordinal fallback).
    ///   - displayUUIDs: monitors to show on; empty ⇒ all monitors.
    ///   - dhssOff: whether Spaces span all displays (one "Main" stack).
    public static func binding(allDesktops: Bool,
                               space: SpaceInfo?,
                               ordinal: Int?,
                               displayUUIDs: [String],
                               dhssOff: Bool) -> Binding {
        if allDesktops || space == nil {
            return Binding(mode: .allSpaces, spaces: [], displayUUIDs: displayUUIDs)
        }
        let space = space!
        let ref = SpaceRef(spaceUUID: space.uuid,
                           spaceID: space.id,
                           displayUUID: dhssOff ? "Main" : nil,
                           ordinalIndex: ordinal)
        return Binding(mode: .spaces, spaces: [ref], displayUUIDs: displayUUIDs)
    }

    /// User-facing desktops for the targeting UI: real (type 0) Spaces only.
    public static func userSpaces(topology: SpacesTopology,
                                  monitorUUID: String?) -> [SpaceInfo] {
        let display: ManagedDisplay?
        if topology.spansDisplays {
            display = topology.displays.first
        } else if let uuid = monitorUUID {
            display = topology.displays.first(where: { $0.displayIdentifier == uuid })
        } else {
            display = topology.displays.first
        }
        return (display?.spaces ?? []).filter { $0.type == .user }
    }
}
