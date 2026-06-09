import XCTest
@testable import DockKit

final class MagnifierTests: XCTestCase {
    private let stride: CGFloat = 60   // 52px icon + 8px gap

    func testPeakScaleDirectlyUnderCursor() {
        XCTAssertEqual(Magnifier.scale(distance: 0, stride: stride), Magnifier.maxScale, accuracy: 0.0001)
    }

    func testFallsToUnityAtAndBeyondInfluenceRadius() {
        let radius = Magnifier.influenceStrides * stride
        XCTAssertEqual(Magnifier.scale(distance: radius, stride: stride), 1, accuracy: 0.0001)
        XCTAssertEqual(Magnifier.scale(distance: radius + 100, stride: stride), 1, accuracy: 0.0001)
    }

    func testSymmetricAroundCursor() {
        XCTAssertEqual(Magnifier.scale(distance: 40, stride: stride),
                       Magnifier.scale(distance: -40, stride: stride), accuracy: 0.0001)
    }

    func testMonotonicDecreaseFromCenterToEdge() {
        let radius = Magnifier.influenceStrides * stride
        var prev = Magnifier.scale(distance: 0, stride: stride)
        var d: CGFloat = 5
        while d <= radius {
            let s = Magnifier.scale(distance: d, stride: stride)
            XCTAssertLessThanOrEqual(s, prev + 0.0001, "scale should not increase moving away from cursor (d=\(d))")
            XCTAssertGreaterThanOrEqual(s, 1)
            prev = s
            d += 5
        }
    }

    func testNeighbourIsMagnifiedButLessThanPeak() {
        let s = Magnifier.scale(distance: stride, stride: stride)   // one icon over
        XCTAssertGreaterThan(s, 1)
        XCTAssertLessThan(s, Magnifier.maxScale)
    }

    func testDegenerateStrideIsSafe() {
        XCTAssertEqual(Magnifier.scale(distance: 10, stride: 0), 1)
    }

    func testHeadroomZeroWhenDisabled() {
        XCTAssertEqual(Magnifier.headroom(iconSize: 52, enabled: false), 0)
    }

    func testHeadroomMatchesPeakGrowthWhenEnabled() {
        let h = Magnifier.headroom(iconSize: 52, enabled: true)
        XCTAssertEqual(h, 52 * (Magnifier.maxScale - 1), accuracy: 0.0001)
        XCTAssertGreaterThan(h, 0)
    }

    func testCustomMaxScaleDrivesPeakAndHeadroom() {
        XCTAssertEqual(Magnifier.scale(distance: 0, stride: stride, maxScale: 2.0), 2.0, accuracy: 0.0001)
        XCTAssertEqual(Magnifier.headroom(iconSize: 50, enabled: true, maxScale: 2.0), 50, accuracy: 0.0001)
        // A larger peak magnifies a neighbour more, same falloff shape.
        XCTAssertGreaterThan(Magnifier.scale(distance: 40, stride: stride, maxScale: 2.0),
                             Magnifier.scale(distance: 40, stride: stride, maxScale: 1.3))
    }

    func testMaxScaleAtOrBelowOneDisablesGrowth() {
        XCTAssertEqual(Magnifier.scale(distance: 0, stride: stride, maxScale: 1.0), 1)
        XCTAssertEqual(Magnifier.headroom(iconSize: 52, enabled: true, maxScale: 1.0), 0)
    }
}
