import Foundation

/// Atomic, backup-protected JSON persistence for the Dockman `Config`
/// (docs/03 §6). Lives at ~/Library/Application Support/xyz.waqas.dockman/config.json.
public final class ConfigStore {
    public let directory: URL
    public let fileURL: URL
    private var backupURL: URL { fileURL.appendingPathExtension("bak") }

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("xyz.waqas.dockman", isDirectory: true)
        self.directory = base
        self.fileURL = base.appendingPathComponent("config.json")
    }

    /// Loads config (migrated forward), falling back to the backup then to `.empty`.
    public func load() -> Config {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: fileURL),
           let config = try? decoder.decode(Config.self, from: data) {
            return Self.migrate(config)
        }
        if let data = try? Data(contentsOf: backupURL),
           let config = try? decoder.decode(Config.self, from: data) {
            return Self.migrate(config)
        }
        return .empty
    }

    /// Forward-only migration chain (docs/03 §6). Field-level defaults are handled
    /// by `DockModel`'s tolerant decoder; this bumps the document version and is the
    /// hook for future structural changes.
    static func migrate(_ config: Config) -> Config {
        var c = config
        // v1 → v2: `Behavior` introduced (defaults applied at decode time).
        if c.schemaVersion < 2 { c.schemaVersion = 2 }
        // Never downgrade a newer file we don't understand.
        c.schemaVersion = max(c.schemaVersion, config.schemaVersion)
        return c
    }

    /// Writes atomically, keeping the previous file as a `.bak`.
    public func save(_ config: Config) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
        }
        try data.write(to: fileURL, options: .atomic)
    }
}
