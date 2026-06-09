import XCTest
import ConfigKit
@testable import DockKit

final class DockItemSupportTests: XCTestCase {

    private let a = DockItem.app(bundlePath: "/A.app", label: nil)
    private let b = DockItem.app(bundlePath: "/B.app", label: nil)
    private let c = DockItem.app(bundlePath: "/C.app", label: nil)

    func testReorderForward() {
        XCTAssertEqual(DockItemOps.reorder([a, b, c], from: 0, to: 3).compactMap(\.appPath),
                       ["/B.app", "/C.app", "/A.app"])
    }
    func testReorderBackward() {
        XCTAssertEqual(DockItemOps.reorder([a, b, c], from: 2, to: 0).compactMap(\.appPath),
                       ["/C.app", "/A.app", "/B.app"])
    }
    func testReorderNoOpOnEqual() {
        XCTAssertEqual(DockItemOps.reorder([a, b, c], from: 1, to: 1), [a, b, c])
    }
    func testInsertAndRemove() {
        let inserted = DockItemOps.insert([a, c], [b], at: 1)
        XCTAssertEqual(inserted.compactMap(\.appPath), ["/A.app", "/B.app", "/C.app"])
        XCTAssertEqual(DockItemOps.removeAt(inserted, 1).compactMap(\.appPath), ["/A.app", "/C.app"])
        XCTAssertEqual(DockItemOps.removeAt([a], 5), [a])   // out of range = no-op
    }

    func testDroppedPathClassification() {
        XCTAssertEqual(DockItemOps.item(forDroppedPath: "/Applications/Whatever.app").appPath,
                       "/Applications/Whatever.app")
        // Non-.app, non-existent path → treated as a file.
        if case .file = DockItemOps.item(forDroppedPath: "/tmp/does-not-exist.txt") {} else {
            XCTFail("expected .file")
        }
    }

    func testRunningZoneExcludesPinnedAndSorts() {
        let running = [
            RunningAppInfo(bundleID: "z", bundlePath: "/Z.app", name: "Zeta", isActive: false),
            RunningAppInfo(bundleID: "a", bundlePath: "/A.app", name: "Alpha", isActive: true),
            RunningAppInfo(bundleID: "m", bundlePath: "/M.app", name: "Mike", isActive: false),
        ]
        let zone = RunningZone.apps(running: running, pinnedAppPaths: ["/M.app"])
        XCTAssertEqual(zone.map(\.name), ["Alpha", "Zeta"])   // Mike pinned-out, sorted
    }

    func testFolderContentsEnumeratesAndSkipsHidden() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dockman-folder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data().write(to: dir.appendingPathComponent("b.txt"))
        try Data().write(to: dir.appendingPathComponent("a.txt"))
        try Data().write(to: dir.appendingPathComponent(".hidden"))

        let names = FolderContents.entries(at: dir.path).map(\.lastPathComponent)
        XCTAssertEqual(names, ["a.txt", "b.txt"])
    }

    func testURLSchemeParsing() {
        XCTAssertEqual(DockmanURL.parse(URL(string: "dockman://toggle?dock=Dev")!), .toggle(dock: "Dev"))
        XCTAssertEqual(DockmanURL.parse(URL(string: "dockman://pin?dock=My%20Dock")!), .pin(dock: "My Dock"))
        XCTAssertEqual(DockmanURL.parse(URL(string: "dockman://show?dock=A")!), .show(dock: "A"))
        XCTAssertNil(DockmanURL.parse(URL(string: "dockman://toggle")!))            // no dock
        XCTAssertNil(DockmanURL.parse(URL(string: "dockman://bogus?dock=A")!))      // bad command
        XCTAssertNil(DockmanURL.parse(URL(string: "https://toggle?dock=A")!))       // wrong scheme
    }
}
