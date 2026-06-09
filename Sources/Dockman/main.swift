import AppKit

// Dockman — Phase 1 walking skeleton. A faceless agent (no system-Dock icon)
// that shows one or more per-Space Docks driven from a menu-bar item.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // agent: no Dock icon, no app menu
app.run()
