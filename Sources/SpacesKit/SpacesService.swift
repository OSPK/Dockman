import Foundation
import CoreGraphics

/// The SIP-safe surface Dockman uses to talk to the WindowServer about Spaces.
///
/// Read methods are always safe (unprotected by the WindowServer). The mutating
/// methods MUST only ever be called with a `CGWindowID` that belongs to one of
/// Dockman's OWN windows — that is the entire SIP-safety argument (docs/02 §2.2):
/// the `connection_holds_rights_on_window` check passes for windows our own
/// connection created, so no SIP change is needed.
public protocol SpacesService: AnyObject {
    /// Which private capabilities resolved at runtime.
    var capabilities: SpacesCapabilities { get }

    /// Snapshot of every display's Space stack plus DHSS topology.
    func managedDisplaySpaces() -> SpacesTopology

    /// The type (user/fullscreen/system) of a Space.
    func spaceType(_ id: UInt64) -> SpaceType

    /// Which Spaces a window currently belongs to.
    func spaces(ofWindow wid: CGWindowID) -> Set<UInt64>

    /// Make `wid` belong to EXACTLY `spaceID` (clears all others). Own windows only.
    func move(window wid: CGWindowID, toExactly spaceID: UInt64)

    /// Make `wid` belong to exactly the given set (diffed add/remove). Own windows only.
    func set(window wid: CGWindowID, spaces: Set<UInt64>)

    /// Add `wid` to `spaces` (kept in others). Own windows only.
    func add(window wid: CGWindowID, toSpaces spaces: Set<UInt64>)

    /// Remove `wid` from `spaces`. Own windows only.
    func remove(window wid: CGWindowID, fromSpaces spaces: Set<UInt64>)
}
