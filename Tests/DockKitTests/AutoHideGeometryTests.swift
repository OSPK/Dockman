import XCTest
import ConfigKit
@testable import DockKit

final class AutoHideGeometryTests: XCTestCase {
    // A 1000x800 screen at origin; a 300x72 dock revealed 16px above the bottom.
    private let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
    private let revealed = NSRect(x: 350, y: 16, width: 300, height: 72)

    func testRevealZoneBottomIsThinEdgeStripUnderTheDock() {
        let zone = DockController.revealZone(edge: .bottom, revealed: revealed, screenFrame: screen)
        XCTAssertEqual(zone.minY, screen.minY)
        XCTAssertEqual(zone.height, 4, accuracy: 0.01)
        // Cursor at the bottom edge under the dock is inside the reveal zone…
        XCTAssertTrue(zone.contains(NSPoint(x: 500, y: 1)))
        // …but the far corner of the screen is not.
        XCTAssertFalse(zone.contains(NSPoint(x: 10, y: 1)))
    }

    func testRevealZoneLeftEdgeIsVerticalStrip() {
        let leftDock = NSRect(x: 16, y: 360, width: 72, height: 300)
        let zone = DockController.revealZone(edge: .left, revealed: leftDock, screenFrame: screen)
        XCTAssertEqual(zone.minX, screen.minX)
        XCTAssertEqual(zone.width, 4, accuracy: 0.01)
        XCTAssertTrue(zone.contains(NSPoint(x: 1, y: 500)))
    }

    // A display at a non-zero origin (like a second monitor) — the Dock must stay
    // fully inside it and never spill onto a neighbour.
    private let offsetScreen = NSRect(x: -1737, y: 1050, width: 2560, height: 1440)

    func testHorizontalDockNeverExceedsDisplayWidth() {
        // An oversized 4000px-wide dock must be capped to the display and stay inside.
        let frame = DockController.frame(for: Appearance(edge: .bottom),
                                         size: NSSize(width: 4000, height: 82),
                                         screenFrame: offsetScreen)
        XCTAssertLessThanOrEqual(frame.width, offsetScreen.width)
        XCTAssertGreaterThanOrEqual(frame.minX, offsetScreen.minX)
        XCTAssertLessThanOrEqual(frame.maxX, offsetScreen.maxX)
    }

    func testVerticalDockNeverExceedsDisplayHeight() {
        // A 9000px-tall left dock (lots of running apps) must be capped and stay inside.
        let frame = DockController.frame(for: Appearance(edge: .left),
                                         size: NSSize(width: 72, height: 9000),
                                         screenFrame: offsetScreen)
        XCTAssertLessThanOrEqual(frame.height, offsetScreen.height)
        XCTAssertGreaterThanOrEqual(frame.minY, offsetScreen.minY)
        XCTAssertLessThanOrEqual(frame.maxY, offsetScreen.maxY)
    }

    func testNormalSizedDockIsCenteredAndInside() {
        let frame = DockController.frame(for: Appearance(edge: .bottom),
                                         size: NSSize(width: 300, height: 82),
                                         screenFrame: offsetScreen)
        XCTAssertEqual(frame.midX, offsetScreen.midX, accuracy: 0.5)
        XCTAssertTrue(offsetScreen.contains(frame))
    }

    func testEdgeGapControlsDistanceFromScreenEdge() {
        let size = NSSize(width: 300, height: 82)
        // Default 16px gap (the historical hardcoded margin).
        let dflt = DockController.frame(for: Appearance(edge: .bottom), size: size, screenFrame: screen)
        XCTAssertEqual(dflt.minY, screen.minY + 16, accuracy: 0.01)
        // Flush against the edge.
        let flush = DockController.frame(for: Appearance(edge: .bottom, edgeGap: 0), size: size, screenFrame: screen)
        XCTAssertEqual(flush.minY, screen.minY, accuracy: 0.01)
        // Wide custom gap, all four edges anchor against their own side.
        let gap: CGFloat = 40
        let a = Appearance(edge: .top, edgeGap: 40)
        XCTAssertEqual(DockController.frame(for: a, size: size, screenFrame: screen).maxY,
                       screen.maxY - gap, accuracy: 0.01)
        let left = Appearance(edge: .left, edgeGap: 40)
        XCTAssertEqual(DockController.frame(for: left, size: NSSize(width: 82, height: 300), screenFrame: screen).minX,
                       screen.minX + gap, accuracy: 0.01)
        let right = Appearance(edge: .right, edgeGap: 40)
        XCTAssertEqual(DockController.frame(for: right, size: NSSize(width: 82, height: 300), screenFrame: screen).maxX,
                       screen.maxX - gap, accuracy: 0.01)
    }
}
