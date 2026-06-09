import AppKit
import ConfigKit

/// A running application as Dockman cares about it (for indicators + the zone).
public struct RunningAppInfo: Equatable {
    public let bundleID: String?
    public let bundlePath: String?
    public let name: String
    public let isActive: Bool
    public init(bundleID: String?, bundlePath: String?, name: String, isActive: Bool) {
        self.bundleID = bundleID
        self.bundlePath = bundlePath
        self.name = name
        self.isActive = isActive
    }
}

/// Pure list operations on Dock items — unit-tested so the drag/drop and context
/// menu glue can stay thin (docs/03 §8).
public enum DockItemOps {
    public static func reorder(_ items: [DockItem], from: Int, to: Int) -> [DockItem] {
        guard items.indices.contains(from), to >= 0, to <= items.count, from != to else { return items }
        var copy = items
        let moved = copy.remove(at: from)
        let dest = to > from ? to - 1 : to
        copy.insert(moved, at: min(max(dest, 0), copy.count))
        return copy
    }

    public static func insert(_ items: [DockItem], _ newItems: [DockItem], at index: Int) -> [DockItem] {
        var copy = items
        copy.insert(contentsOf: newItems, at: min(max(index, 0), copy.count))
        return copy
    }

    public static func removeAt(_ items: [DockItem], _ index: Int) -> [DockItem] {
        guard items.indices.contains(index) else { return items }
        var copy = items
        copy.remove(at: index)
        return copy
    }

    /// Classify a dropped file URL into the right Dock item kind. `.app` bundles are
    /// apps; other directories become folder stacks; everything else is a file.
    public static func item(forDroppedPath path: String) -> DockItem {
        if path.hasSuffix(".app") {
            return .app(bundlePath: path, label: nil)
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            return .folder(path: path, label: nil, style: .grid)
        }
        return .file(path: path, label: nil)
    }
}

/// Which running apps the dynamic "running apps" zone should show.
public enum RunningZone {
    /// Running apps not already pinned in the Dock, stable-sorted by name.
    public static func apps(running: [RunningAppInfo], pinnedAppPaths: Set<String>) -> [RunningAppInfo] {
        running
            .filter { info in
                guard let path = info.bundlePath else { return true }
                return !pinnedAppPaths.contains(path)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Folder enumeration for folder stacks.
public enum FolderContents {
    public static func entries(at path: String, limit: Int = 100) -> [URL] {
        let url = URL(fileURLWithPath: path)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return items
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(limit)
            .map { $0 }
    }
}
