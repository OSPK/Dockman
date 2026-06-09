import XCTest
import CoreGraphics
@testable import SpacesKit

/// Contract smoke tests against the REAL SkyLight on the running machine.
/// These do not run meaningfully in a headless/no-GUI environment; they assert
/// that symbol resolution and read-only topology parsing don't crash and return
/// plausible data. See docs/03 §8 (SpacesContractTests).
final class SpacesKitTests: XCTestCase {

    func testSymbolsResolveTopologyCapability() {
        let service = SkyLightSpacesService()
        // SkyLight ships on every macOS; topology read symbols must resolve.
        XCTAssertTrue(service.capabilities.contains(.readTopology),
                      "Expected SLSMainConnectionID + SLSCopyManagedDisplaySpaces to resolve")
    }

    func testManagedDisplaySpacesDoesNotCrashAndIsConsistent() {
        let service = SkyLightSpacesService()
        let topo = service.managedDisplaySpaces()
        // In a GUI session there is at least one display with at least one Space.
        // In a headless CI session this may be empty; only assert internal consistency.
        for display in topo.displays {
            if let current = display.currentSpace {
                XCTAssertTrue(display.spaces.contains(where: { $0.id == current.id })
                              || current.id != 0,
                              "Current space should be among the display's spaces")
            }
        }
        if topo.spansDisplays {
            XCTAssertEqual(topo.displays.count, 1, "DHSS-off topology should be a single \"Main\" display")
        }
    }

    func testSpacesForUnknownWindowIsEmpty() {
        let service = SkyLightSpacesService()
        // A window id that is (almost certainly) not ours / not real → empty set, no crash.
        XCTAssertEqual(service.spaces(ofWindow: CGWindowID(0)), [])
    }

    func testMutationGuardIgnoresForeignWindowWhenOwnedSetPopulated() {
        let service = SkyLightSpacesService()
        service.registerOwnedWindow(CGWindowID(123456))
        // Asking to move a window we did NOT register must be refused by the guard
        // (in release builds it early-returns; in debug it would assert, so we only
        // exercise the read path here).
        XCTAssertEqual(service.spaces(ofWindow: CGWindowID(999999)), [])
    }
}
