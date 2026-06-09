import XCTest
import SpacesKit
import ConfigKit
@testable import DockKit

final class BindingResolverTests: XCTestCase {

    // A DHSS-off topology like the dev machine: one "Main" display, empty UUIDs.
    private func topology(spaceIDs: [UInt64], current: UInt64, uuids: [UInt64: String] = [:]) -> SpacesTopology {
        let spaces = spaceIDs.map { SpaceInfo(id: $0, uuid: uuids[$0], type: .user) }
        let display = ManagedDisplay(
            displayIdentifier: "Main",
            currentSpace: spaces.first { $0.id == current },
            spaces: spaces
        )
        return SpacesTopology(displays: [display], spansDisplays: true)
    }

    // Regression: empty/absent UUID must NOT match the first empty-UUID Space;
    // resolution must fall through to spaceID (the bug found during Phase-1 bring-up).
    func testEmptyUUIDFallsThroughToSpaceID() {
        let topo = topology(spaceIDs: [1, 4, 5], current: 1)
        let binding = Binding(mode: .spaces, spaces: [
            SpaceRef(spaceUUID: "", spaceID: 4, displayUUID: "Main", ordinalIndex: 1)
        ])
        XCTAssertEqual(BindingResolver.resolve(binding, topology: topo, displayUUID: "Main"), [4])
    }

    func testNilUUIDResolvesBySpaceID() {
        let topo = topology(spaceIDs: [1, 4, 5], current: 1)
        let binding = Binding(mode: .spaces, spaces: [SpaceRef(spaceID: 5)])
        XCTAssertEqual(BindingResolver.resolve(binding, topology: topo, displayUUID: nil), [5])
    }

    func testNonEmptyUUIDWins() {
        let topo = topology(spaceIDs: [1, 4, 5], current: 1, uuids: [5: "ABC-5"])
        // Stale spaceID 99 but valid UUID → resolve by UUID.
        let binding = Binding(mode: .spaces, spaces: [SpaceRef(spaceUUID: "ABC-5", spaceID: 99)])
        XCTAssertEqual(BindingResolver.resolve(binding, topology: topo, displayUUID: nil), [5])
    }

    func testOrdinalFallbackWhenIDChanged() {
        let topo = topology(spaceIDs: [10, 11, 12], current: 10)
        // UUID empty and spaceID 4 no longer exists; ordinal 2 → third space (12).
        let binding = Binding(mode: .spaces, spaces: [
            SpaceRef(spaceUUID: "", spaceID: 4, displayUUID: "Main", ordinalIndex: 2)
        ])
        XCTAssertEqual(BindingResolver.resolve(binding, topology: topo, displayUUID: "Main"), [12])
    }

    func testMultipleSpaces() {
        let topo = topology(spaceIDs: [1, 4, 5], current: 1)
        let binding = Binding(mode: .spaces, spaces: [SpaceRef(spaceID: 1), SpaceRef(spaceID: 5)])
        XCTAssertEqual(BindingResolver.resolve(binding, topology: topo, displayUUID: nil), [1, 5])
    }

    func testAllSpacesResolvesEmpty() {
        let topo = topology(spaceIDs: [1, 4, 5], current: 1)
        XCTAssertEqual(BindingResolver.resolve(.allSpaces, topology: topo, displayUUID: nil), [])
    }

    // --- Phase 2: exact vs ordinal distinction (login churn vs live delete) ---

    func testExactMatchReportedExactly() {
        let topo = topology(spaceIDs: [1, 4, 5], current: 1)
        let binding = Binding(mode: .spaces, spaces: [SpaceRef(spaceID: 4, ordinalIndex: 1)])
        let r = BindingResolver.resolveDetailed(binding, topology: topo, displayUUID: "Main", allowOrdinal: true)
        XCTAssertEqual(r.spaceIDs, [4])
        XCTAssertTrue(r.matchedExactly)
    }

    func testOrdinalMatchReportedInexact() {
        // IDs churned (now 10,11,12); bound id 4 gone but ordinal 1 → 11.
        let topo = topology(spaceIDs: [10, 11, 12], current: 10)
        let binding = Binding(mode: .spaces, spaces: [SpaceRef(spaceID: 4, ordinalIndex: 1)])
        let r = BindingResolver.resolveDetailed(binding, topology: topo, displayUUID: "Main", allowOrdinal: true)
        XCTAssertEqual(r.spaceIDs, [11])
        XCTAssertFalse(r.matchedExactly)   // only ordinal matched
    }

    func testOrdinalSuppressedWhenDisallowed() {
        // After an exact match earlier, we forbid ordinal → bound Space truly gone.
        let topo = topology(spaceIDs: [10, 11, 12], current: 10)
        let binding = Binding(mode: .spaces, spaces: [SpaceRef(spaceID: 4, ordinalIndex: 1)])
        let r = BindingResolver.resolveDetailed(binding, topology: topo, displayUUID: "Main", allowOrdinal: false)
        XCTAssertTrue(r.spaceIDs.isEmpty)   // orphaned: do NOT grab a neighbor
    }

    func testOrphanDetection() {
        let topo = topology(spaceIDs: [1, 4, 5], current: 1)
        // spaceID 99 gone, no uuid, no ordinal → orphaned.
        let orphan = Binding(mode: .spaces, spaces: [SpaceRef(spaceID: 99)])
        XCTAssertTrue(BindingResolver.isOrphaned(orphan, topology: topo, displayUUID: "Main"))

        let ok = Binding(mode: .spaces, spaces: [SpaceRef(spaceID: 4)])
        XCTAssertFalse(BindingResolver.isOrphaned(ok, topology: topo, displayUUID: "Main"))
    }
}
