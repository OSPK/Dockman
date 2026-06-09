import XCTest
@testable import DockKit

/// The pure drop-insertion computation behind drag-reorder. `centers` are
/// (modelIndex, center-along-axis) in model order; the result is an index into
/// the full `items` array — separators and spacers count, zone synthetics don't.
final class InsertionIndexTests: XCTestCase {

    // Horizontal dock: items [A(0) sep(1) B(2)] at x = 50, 110, 170; 3 model items.
    private let horizontal: [(index: Int, center: CGFloat)] = [(0, 50), (1, 110), (2, 170)]

    func testDropBeforeFirstItem() {
        XCTAssertEqual(DockContentView.insertionIndex(cursor: 10, centers: horizontal,
                                                      descending: false, itemCount: 3), 0)
    }

    func testDropBetweenIconAndSeparatorLandsAtSeparatorSlot() {
        XCTAssertEqual(DockContentView.insertionIndex(cursor: 80, centers: horizontal,
                                                      descending: false, itemCount: 3), 1)
    }

    func testDropAfterSeparatorCountsTheSeparator() {
        // Cursor between separator (110) and B (170): insertion at model index 2 —
        // the old cell-only counting would have said 1 and put the drop before the
        // separator.
        XCTAssertEqual(DockContentView.insertionIndex(cursor: 140, centers: horizontal,
                                                      descending: false, itemCount: 3), 2)
    }

    func testDropPastLastItemAppends() {
        XCTAssertEqual(DockContentView.insertionIndex(cursor: 400, centers: horizontal,
                                                      descending: false, itemCount: 3), 3)
    }

    func testDropInZoneAreaAppendsAfterZone() {
        // [A(0) zone(1)]: zone-synthetic cells render with no model index, so only
        // A reports a center. A drop to the right of A appends after the zone item.
        XCTAssertEqual(DockContentView.insertionIndex(cursor: 300, centers: [(0, 50)],
                                                      descending: false, itemCount: 2), 2)
    }

    func testVerticalDockUsesDescendingY() {
        // Vertical dock: first item is at the TOP, i.e. the LARGEST Cocoa y.
        // Items [A(0) B(1) C(2)] at y = 170, 110, 50.
        let vertical: [(index: Int, center: CGFloat)] = [(0, 170), (1, 110), (2, 50)]
        XCTAssertEqual(DockContentView.insertionIndex(cursor: 200, centers: vertical,
                                                      descending: true, itemCount: 3), 0)  // above A
        XCTAssertEqual(DockContentView.insertionIndex(cursor: 140, centers: vertical,
                                                      descending: true, itemCount: 3), 1)  // between A and B
        XCTAssertEqual(DockContentView.insertionIndex(cursor: 10, centers: vertical,
                                                      descending: true, itemCount: 3), 3)  // below C
    }

    func testEmptyDockAppendsAtZero() {
        XCTAssertEqual(DockContentView.insertionIndex(cursor: 100, centers: [],
                                                      descending: false, itemCount: 0), 0)
    }
}
