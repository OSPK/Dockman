import XCTest
@testable import ConfigKit

final class ConfigKitTests: XCTestCase {

    func testConfigRoundTripsThroughJSON() throws {
        let dock = DockModel(
            name: "Dev",
            items: [
                .app(bundlePath: "/System/Applications/Notes.app", label: nil),
                .separator,
                .app(bundlePath: "/Applications/Safari.app", label: "Browser"),
            ],
            binding: Binding(mode: .spaces,
                             spaces: [SpaceRef(spaceUUID: "ABC", spaceID: 7, displayUUID: "Main", ordinalIndex: 2)]),
            appearance: Appearance(edge: .bottom, iconSize: 52)
        )
        let config = Config(docks: [dock])

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(Config.self, from: data)

        XCTAssertEqual(config, decoded)
        XCTAssertEqual(decoded.docks.first?.binding.spaces.first?.spaceID, 7)
        XCTAssertEqual(decoded.docks.first?.items.count, 3)
    }

    func testStoreSavesAndLoadsAtomicallyWithBackup() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dockman-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = ConfigStore(directory: tmp)
        XCTAssertEqual(store.load(), .empty, "Missing file loads empty")

        var config = Config(docks: [DockModel(name: "A", items: [.separator], binding: .allSpaces)])
        try store.save(config)
        XCTAssertEqual(store.load().docks.first?.name, "A")

        // Saving again should produce a .bak of the previous version.
        config.docks[0].name = "B"
        try store.save(config)
        XCTAssertEqual(store.load().docks.first?.name, "B")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.appendingPathExtension("bak").path))
    }

    func testLoadsLegacyV1ConfigWithoutBehaviorAndMigrates() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dockman-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        // A v1 document: schemaVersion 1, dock has no "behavior" or "appearance" key.
        let legacy = """
        {
          "schemaVersion": 1,
          "global": { "launchAtLogin": false },
          "docks": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "name": "Legacy",
              "items": [ { "separator": {} } ],
              "binding": { "mode": "allSpaces", "spaces": [], "displayUUIDs": [] },
              "enabled": true
            }
          ]
        }
        """
        let store = ConfigStore(directory: tmp)
        try Data(legacy.utf8).write(to: store.fileURL)

        let loaded = store.load()
        XCTAssertEqual(loaded.schemaVersion, Config.currentSchemaVersion)   // migrated forward
        XCTAssertEqual(loaded.docks.first?.name, "Legacy")
        XCTAssertEqual(loaded.docks.first?.behavior, Behavior())            // default applied
        XCTAssertEqual(loaded.docks.first?.appearance, Appearance())        // default applied
    }

    func testMagnificationDefaultsFalseWhenAbsentAndRoundTrips() throws {
        // An Appearance written before `magnification` existed keeps its other fields
        // and defaults the new flag off.
        let legacyAppearance = #"{ "edge": "top", "iconSize": 64, "style": "solid" }"#
        let decoded = try JSONDecoder().decode(Appearance.self, from: Data(legacyAppearance.utf8))
        XCTAssertEqual(decoded.edge, .top)
        XCTAssertEqual(decoded.iconSize, 64)
        XCTAssertFalse(decoded.magnification)

        // Round-trip with the flag on.
        let on = Appearance(edge: .left, iconSize: 48, style: .classic, magnification: true)
        let reloaded = try JSONDecoder().decode(Appearance.self, from: JSONEncoder().encode(on))
        XCTAssertEqual(reloaded, on)
        XCTAssertTrue(reloaded.magnification)
    }

    func testPaddingAndEdgeGapDefaultWhenAbsentAndRoundTrip() throws {
        // Configs written before margin/edge-gap existed get the historical values
        // (10px padding, 16px gap) so existing docks don't visually shift.
        let legacy = #"{ "edge": "bottom", "iconSize": 52 }"#
        let decoded = try JSONDecoder().decode(Appearance.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.padding, Appearance.defaultPadding)
        XCTAssertEqual(decoded.edgeGap, Appearance.defaultEdgeGap)

        let custom = Appearance(padding: 4, edgeGap: 0)
        let reloaded = try JSONDecoder().decode(Appearance.self, from: JSONEncoder().encode(custom))
        XCTAssertEqual(reloaded.padding, 4)
        XCTAssertEqual(reloaded.edgeGap, 0)
    }

    // Dev helper: writes a Dock exercising every item kind to the real config path.
    // Runs only when DOCKMAN_DEMO=1 so normal test passes are unaffected.
    func testWriteRichDemoConfig() throws {
        guard ProcessInfo.processInfo.environment["DOCKMAN_DEMO"] == "1" else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let store = ConfigStore(directory: home.appendingPathComponent("Library/Application Support/xyz.waqas.dockman"))
        let items: [DockItem] = [
            .app(bundlePath: "/System/Library/CoreServices/Finder.app", label: nil),
            .app(bundlePath: "/System/Applications/Notes.app", label: nil),
            .separator,
            .folder(path: home.appendingPathComponent("Downloads").path, label: "Downloads", style: .grid),
            .action(DockAction(kind: .openURL, value: "https://www.apple.com", label: "Apple", symbol: "safari.fill")),
            .spacer(points: 16),
            .runningAppsZone,
        ]
        try store.save(Config(docks: [DockModel(name: "Rich", items: items, binding: .allSpaces)]))
    }

    func testCorruptFileFallsBackToBackup() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dockman-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = ConfigStore(directory: tmp)
        try store.save(Config(docks: [DockModel(name: "Good", items: [.separator], binding: .allSpaces)]))
        try store.save(Config(docks: [DockModel(name: "Good2", items: [.separator], binding: .allSpaces)]))

        // Corrupt the primary file; loader should recover the .bak ("Good").
        try Data("{ not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(store.load().docks.first?.name, "Good")
    }
}
