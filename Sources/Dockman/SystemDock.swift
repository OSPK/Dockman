import AppKit

/// Hides/restores the built-in macOS Dock via its documented `autohide` preference
/// (docs/05 R-17). We remember the prior value so restore is exact, and a failsafe
/// "Restore System Dock" path is always available.
enum SystemDock {
    /// The system Dock's current autohide setting.
    static var autohide: Bool {
        UserDefaults(suiteName: "com.apple.dock")?.bool(forKey: "autohide") ?? false
    }

    /// Hide the Dock far off-screen (autohide + a huge reveal delay so it never peeks).
    static func hide() {
        defaultsWrite(["write", "com.apple.dock", "autohide", "-bool", "true"])
        defaultsWrite(["write", "com.apple.dock", "autohide-delay", "-float", "1000"])
        restartDock()
    }

    /// Restore to `priorAutohide` and remove our reveal-delay override.
    static func restore(priorAutohide: Bool) {
        defaultsWrite(["delete", "com.apple.dock", "autohide-delay"])
        defaultsWrite(["write", "com.apple.dock", "autohide", "-bool", priorAutohide ? "true" : "false"])
        restartDock()
    }

    private static func defaultsWrite(_ args: [String]) {
        run("/usr/bin/defaults", args)
    }
    private static func restartDock() {
        run("/usr/bin/killall", ["Dock"])
    }
    private static func run(_ path: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try? process.run()
        process.waitUntilExit()
    }
}
