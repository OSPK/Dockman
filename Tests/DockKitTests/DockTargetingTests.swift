import XCTest
import SpacesKit
import ConfigKit
@testable import DockKit

final class DockTargetingTests: XCTestCase {

    private let s3 = SpaceInfo(id: 3, uuid: nil, type: .user)

    // DHSS OFF: orthogonal axes — desktop + a subset of monitors.
    func testDHSSOffPinsSpaceAndMonitorSubset() {
        let b = DockTargeting.binding(allDesktops: false, space: s3, ordinal: 1,
                                      displayUUIDs: ["MON-B"], dhssOff: true)
        XCTAssertEqual(b.mode, .spaces)
        XCTAssertEqual(b.spaces.first?.spaceID, 3)
        XCTAssertEqual(b.spaces.first?.displayUUID, "Main")   // shared stack marker
        XCTAssertEqual(b.spaces.first?.ordinalIndex, 1)
        XCTAssertEqual(b.displayUUIDs, ["MON-B"])
    }

    // DHSS ON: coupled — space lives in a specific monitor's stack.
    func testDHSSOnPinsSpaceOnItsMonitor() {
        let b = DockTargeting.binding(allDesktops: false, space: s3, ordinal: 2,
                                      displayUUIDs: ["MON-A"], dhssOff: false)
        XCTAssertEqual(b.spaces.first?.spaceID, 3)
        XCTAssertNil(b.spaces.first?.displayUUID)             // no shared marker
        XCTAssertEqual(b.displayUUIDs, ["MON-A"])
    }

    func testAllDesktopsKeepsMonitorScope() {
        let b = DockTargeting.binding(allDesktops: true, space: s3, ordinal: 0,
                                      displayUUIDs: ["MON-A", "MON-B"], dhssOff: true)
        XCTAssertEqual(b.mode, .allSpaces)
        XCTAssertTrue(b.spaces.isEmpty)
        XCTAssertEqual(b.displayUUIDs, ["MON-A", "MON-B"])
    }

    func testNoSpaceFallsBackToAllSpaces() {
        let b = DockTargeting.binding(allDesktops: false, space: nil, ordinal: nil,
                                      displayUUIDs: [], dhssOff: true)
        XCTAssertEqual(b.mode, .allSpaces)
        XCTAssertTrue(b.displayUUIDs.isEmpty)
    }

    func testUserSpacesExcludesFullscreen() {
        let spaces = [
            SpaceInfo(id: 1, uuid: nil, type: .user),
            SpaceInfo(id: 2, uuid: nil, type: .fullscreen),
            SpaceInfo(id: 3, uuid: nil, type: .user),
        ]
        let topo = SpacesTopology(
            displays: [ManagedDisplay(displayIdentifier: "Main", currentSpace: spaces[0], spaces: spaces)],
            spansDisplays: true)
        let userSpaces = DockTargeting.userSpaces(topology: topo, monitorUUID: nil)
        XCTAssertEqual(userSpaces.map(\.id), [1, 3])
    }
}
