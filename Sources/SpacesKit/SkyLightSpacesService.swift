import Foundation
import CoreGraphics

/// Concrete `SpacesService` backed by the private SkyLight framework.
///
/// All mutating calls funnel through `assertOwnWindow(_:)` so "only touch our own
/// windows" is a structural property (docs/02 §3.4). In this Phase-0 build the
/// ownership set is empty by default and the guard is advisory; the full app
/// registers each Dock window's number so the assertion has teeth.
public final class SkyLightSpacesService: SpacesService {
    private let symbols = SkyLightSymbols()

    /// Window numbers Dockman created and is therefore permitted to move.
    /// Empty ⇒ guard is advisory (used by the spike, which owns the only window).
    private var ownedWindows: Set<CGWindowID> = []

    public init() {}

    public func registerOwnedWindow(_ wid: CGWindowID)   { ownedWindows.insert(wid) }
    public func unregisterOwnedWindow(_ wid: CGWindowID) { ownedWindows.remove(wid) }

    public var capabilities: SpacesCapabilities {
        var caps: SpacesCapabilities = []
        if symbols.mainConnectionID != nil, symbols.copyManagedDisplaySpaces != nil { caps.insert(.readTopology) }
        if symbols.copySpacesForWindows != nil    { caps.insert(.readWindowSpaces) }
        if symbols.moveWindowsToManagedSpace != nil { caps.insert(.moveWindows) }
        if symbols.addWindowsToSpaces != nil, symbols.removeWindowsFromSpaces != nil { caps.insert(.addRemoveWindows) }
        if symbols.spaceGetType != nil            { caps.insert(.spaceType) }
        return caps
    }

    // MARK: Reads

    public func managedDisplaySpaces() -> SpacesTopology {
        guard let conn = symbols.mainConnectionID?(),
              let cf = symbols.copyManagedDisplaySpaces?(conn)?.takeRetainedValue()
        else { return SpacesTopology(displays: [], spansDisplays: false) }

        let entries = (cf as NSArray).compactMap { $0 as? [String: Any] }
        var displays: [ManagedDisplay] = []
        for entry in entries {
            let ident = (entry["Display Identifier"] as? String) ?? "?"
            let spacesRaw = (entry["Spaces"] as? [[String: Any]]) ?? []
            let spaces = spacesRaw.map(Self.parseSpace)
            let current = (entry["Current Space"] as? [String: Any]).map(Self.parseSpace)
            displays.append(ManagedDisplay(displayIdentifier: ident, currentSpace: current, spaces: spaces))
        }
        // DHSS OFF is reported as a single "Main" managed display whose spaces span
        // all physical screens.
        let spans = displays.count == 1 && displays.first?.displayIdentifier == "Main"
        return SpacesTopology(displays: displays, spansDisplays: spans)
    }

    public func spaceType(_ id: UInt64) -> SpaceType {
        guard let conn = symbols.mainConnectionID?(), let fn = symbols.spaceGetType else { return .unknown }
        return SpaceType(rawValue: Int(fn(conn, id))) ?? .unknown
    }

    public func spaces(ofWindow wid: CGWindowID) -> Set<UInt64> {
        guard let conn = symbols.mainConnectionID?(), let fn = symbols.copySpacesForWindows else { return [] }
        // mask 0x7 = current | other | all
        guard let cf = fn(conn, 0x7, Self.cfArray([NSNumber(value: wid)]))?.takeRetainedValue() else { return [] }
        let nums = (cf as NSArray).compactMap { ($0 as? NSNumber)?.uint64Value }
        return Set(nums)
    }

    // MARK: Mutations (own windows only)

    public func move(window wid: CGWindowID, toExactly spaceID: UInt64) {
        guard assertOwnWindow(wid), let conn = symbols.mainConnectionID?(),
              let fn = symbols.moveWindowsToManagedSpace else { return }
        fn(conn, Self.cfArray([NSNumber(value: wid)]), spaceID)
    }

    public func set(window wid: CGWindowID, spaces target: Set<UInt64>) {
        guard !target.isEmpty else { return }
        // Use the ATOMIC move-to-exactly-one-space as the base operation: it clears
        // membership of all other Spaces in a single WindowServer call, avoiding the
        // read-then-diff race where a just-ordered window is still being assigned to
        // the active Space (docs/05 R-15). Then add any remaining target Spaces.
        let ordered = target.sorted()
        move(window: wid, toExactly: ordered[0])
        let rest = Set(ordered.dropFirst())
        if !rest.isEmpty { add(window: wid, toSpaces: rest) }
    }

    public func add(window wid: CGWindowID, toSpaces spaces: Set<UInt64>) {
        guard assertOwnWindow(wid), let conn = symbols.mainConnectionID?(),
              let fn = symbols.addWindowsToSpaces else { return }
        fn(conn, Self.cfArray([NSNumber(value: wid)]), Self.cfArray(spaces.map { NSNumber(value: $0) }))
    }

    public func remove(window wid: CGWindowID, fromSpaces spaces: Set<UInt64>) {
        guard assertOwnWindow(wid), let conn = symbols.mainConnectionID?(),
              let fn = symbols.removeWindowsFromSpaces else { return }
        fn(conn, Self.cfArray([NSNumber(value: wid)]), Self.cfArray(spaces.map { NSNumber(value: $0) }))
    }

    // MARK: Helpers

    /// SIP-safety guard. When the owned set is populated, refuses foreign windows.
    private func assertOwnWindow(_ wid: CGWindowID) -> Bool {
        guard !ownedWindows.isEmpty else { return true }   // advisory mode (spike)
        assert(ownedWindows.contains(wid), "SpacesService asked to move a window Dockman does not own (\(wid))")
        return ownedWindows.contains(wid)
    }

    private static func cfArray(_ numbers: [NSNumber]) -> CFArray { numbers as CFArray }

    private static func parseSpace(_ d: [String: Any]) -> SpaceInfo {
        let id = (d["ManagedSpaceID"] as? NSNumber)?.uint64Value
            ?? (d["id64"] as? NSNumber)?.uint64Value
            ?? 0
        // Some macOS builds report an empty "uuid" — treat that as absent so the
        // composite binding key falls through to id/ordinal (docs/02 §5).
        let uuidRaw = d["uuid"] as? String
        let uuid = (uuidRaw?.isEmpty == false) ? uuidRaw : nil
        let typeRaw = (d["type"] as? NSNumber)?.intValue ?? -1
        return SpaceInfo(id: id, uuid: uuid, type: SpaceType(rawValue: typeRaw) ?? .unknown)
    }
}
