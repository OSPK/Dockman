import XCTest
@testable import DockKit

final class AXWindowControlTests: XCTestCase {
    // Primary (menu-bar) screen 1680x1050 at origin; flip line = 1050.
    private let primaryMaxY: CGFloat = 1050

    func testCentersOnPrimaryScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1680, height: 1050)
        let p = AXWindowControl.centeredTopLeft(windowSize: CGSize(width: 800, height: 600),
                                                screenFrame: screen, primaryMaxY: primaryMaxY)
        // Centered horizontally: x = 840 - 400 = 440.
        XCTAssertEqual(p.x, 440, accuracy: 0.5)
        // Cocoa top = midY(525)+300 = 825 → AX y = 1050 - 825 = 225.
        XCTAssertEqual(p.y, 225, accuracy: 0.5)
    }

    func testCentersOnSecondaryScreenAbovePrimary() {
        // A monitor positioned above the primary (Cocoa y 1050..2490) → negative AX y.
        let screen = NSRect(x: 823, y: 1050, width: 2560, height: 1440)
        let p = AXWindowControl.centeredTopLeft(windowSize: CGSize(width: 1000, height: 800),
                                                screenFrame: screen, primaryMaxY: primaryMaxY)
        XCTAssertEqual(p.x, screen.midX - 500, accuracy: 0.5)
        // Cocoa top = midY(1770)+400 = 2170 → AX y = 1050 - 2170 = -1120 (above primary).
        XCTAssertEqual(p.y, -1120, accuracy: 0.5)
    }

    func testOversizeWindowClampedToScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1680, height: 1050)
        let p = AXWindowControl.centeredTopLeft(windowSize: CGSize(width: 5000, height: 5000),
                                                screenFrame: screen, primaryMaxY: primaryMaxY)
        // Width/height capped to the screen, so it sits at the screen's top-left.
        XCTAssertEqual(p.x, 0, accuracy: 0.5)
        XCTAssertEqual(p.y, 0, accuracy: 0.5)
    }
}
