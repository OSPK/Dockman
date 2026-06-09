import Foundation
import ConfigKit
import SpacesKit

/// Resolves a persisted `Binding` to concrete Managed Space IDs against the
/// current topology, using the composite key uuid → id → ordinal (docs/02 §5).
public enum BindingResolver {

    /// Result of a resolution, distinguishing exact matches (uuid/id) from the
    /// ordinal fallback. The caller uses this to tell apart legitimate ID churn at
    /// login (ordinal is correct) from a Space that was deleted live (orphan).
    public struct Resolution: Equatable {
        public var spaceIDs: Set<UInt64>
        public var matchedExactly: Bool
        public init(spaceIDs: Set<UInt64>, matchedExactly: Bool) {
            self.spaceIDs = spaceIDs
            self.matchedExactly = matchedExactly
        }
    }

    /// Full resolution. `allowOrdinal` lets the caller forbid the ordinal fallback
    /// (e.g. after we've already had an exact match this session, so an exact miss
    /// now means the Space was deleted rather than IDs churning).
    public static func resolveDetailed(_ binding: Binding,
                                       topology: SpacesTopology,
                                       displayUUID: String?,
                                       allowOrdinal: Bool) -> Resolution {
        guard binding.mode == .spaces else { return Resolution(spaceIDs: [], matchedExactly: true) }
        let display = pickDisplay(topology: topology, displayUUID: displayUUID)
        var ids: Set<UInt64> = []
        var anyResolved = false
        var anyOrdinalOnly = false
        for ref in binding.spaces {
            if let (id, exact) = resolveOne(ref, in: display, topology: topology, allowOrdinal: allowOrdinal) {
                ids.insert(id)
                anyResolved = true
                if !exact { anyOrdinalOnly = true }
            }
        }
        return Resolution(spaceIDs: ids, matchedExactly: anyResolved && !anyOrdinalOnly)
    }

    /// Convenience: just the Space IDs (ordinal fallback allowed).
    public static func resolve(_ binding: Binding,
                               topology: SpacesTopology,
                               displayUUID: String?) -> Set<UInt64> {
        resolveDetailed(binding, topology: topology, displayUUID: displayUUID, allowOrdinal: true).spaceIDs
    }

    /// True when no Space ref resolves at all (everything gone).
    public static func isOrphaned(_ binding: Binding,
                                  topology: SpacesTopology,
                                  displayUUID: String?) -> Bool {
        guard binding.mode == .spaces, !binding.spaces.isEmpty else { return false }
        return resolve(binding, topology: topology, displayUUID: displayUUID).isEmpty
    }

    private static func pickDisplay(topology: SpacesTopology, displayUUID: String?) -> ManagedDisplay? {
        // DHSS OFF: one "Main" display owns all Spaces, regardless of physical screen.
        if topology.spansDisplays { return topology.displays.first }
        if let uuid = displayUUID,
           let display = topology.displays.first(where: { $0.displayIdentifier == uuid }) {
            return display
        }
        return topology.displays.first
    }

    /// Returns (spaceID, matchedExactly) or nil.
    private static func resolveOne(_ ref: SpaceRef,
                                   in display: ManagedDisplay?,
                                   topology: SpacesTopology,
                                   allowOrdinal: Bool) -> (UInt64, Bool)? {
        // 1. Stable UUID match (ignore empty UUIDs — some macOS builds report them).
        if let uuid = ref.spaceUUID, !uuid.isEmpty,
           let match = topology.allSpaces.first(where: { $0.uuid == uuid }) {
            return (match.id, true)
        }
        // 2. Exact id still present.
        if let id = ref.spaceID, topology.allSpaces.contains(where: { $0.id == id }) {
            return (id, true)
        }
        // 3. Ordinal position within the display's stack (fallback only).
        if allowOrdinal, let ordinal = ref.ordinalIndex, let display,
           ordinal >= 0, ordinal < display.spaces.count {
            return (display.spaces[ordinal].id, false)
        }
        return nil
    }
}
