import AppKit
import SpacesKit

// Dockman — Phase-0 feasibility spike (the roadmap gate).
//
// Proves, on THIS machine with SIP enabled, that an app can pin one of its OWN
// borderless windows to a specific Space via SkyLight — including with "Displays
// have separate Spaces" OFF and across multiple displays.
//
//   --once   : run the pin→read-back round-trip, print PASS/FAIL, exit.
//   (default): also stay alive and report live Space switches so you can
//              visually confirm the dock appears only on its bound desktop.

let runOnce = CommandLine.arguments.contains("--once")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // faceless agent; no system-Dock icon

let service = SkyLightSpacesService()

func line(_ s: String = "") { print(s); fflush(stdout) }

line("== Dockman Phase-0 Spike ==")
line("Capabilities resolved: \(service.capabilities.description)")
guard service.capabilities.contains(.readTopology) else {
    line("❌ FAIL: could not resolve SkyLight topology symbols.")
    exit(2)
}

// --- Topology ---------------------------------------------------------------
let topo = service.managedDisplaySpaces()
line("")
line("\"Displays have separate Spaces\" is OFF (spans-displays): \(topo.spansDisplays)")
for d in topo.displays {
    let ids = d.spaces.map { "\($0.id)(t\($0.type.rawValue))" }.joined(separator: " ")
    line("  display \(d.displayIdentifier): current=\(d.currentSpace?.id ?? 0)  spaces=[\(ids)]")
}

// --- Build a borderless dock-like panel -------------------------------------
func mainDisplayUUID() -> String? {
    let did = CGMainDisplayID()
    guard let cf = CGDisplayCreateUUIDFromDisplayID(did)?.takeRetainedValue() else { return nil }
    return CFUUIDCreateString(nil, cf) as String?
}

let screen = NSScreen.main ?? NSScreen.screens.first!
let size = NSSize(width: 360, height: 84)
let frame = NSRect(x: screen.frame.midX - size.width / 2,
                   y: screen.frame.minY + 48,
                   width: size.width, height: size.height)

let panel = NSPanel(contentRect: frame,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
panel.isFloatingPanel = true
panel.hidesOnDeactivate = false
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
// IMPORTANT: no .canJoinAllSpaces — we manage Space membership ourselves.
panel.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary]

let content = NSView(frame: NSRect(origin: .zero, size: size))
content.wantsLayer = true
content.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.9).cgColor
content.layer?.cornerRadius = 20
let label = NSTextField(labelWithString: "🟦 Dockman — pinned dock")
label.textColor = .white
label.font = .systemFont(ofSize: 15, weight: .semibold)
label.frame = NSRect(x: 18, y: 32, width: size.width - 36, height: 20)
content.addSubview(label)
let sub = NSTextField(labelWithString: "should appear on ONE desktop only")
sub.textColor = .white.withAlphaComponent(0.85)
sub.font = .systemFont(ofSize: 11)
sub.frame = NSRect(x: 18, y: 12, width: size.width - 36, height: 16)
content.addSubview(sub)
panel.contentView = content
panel.orderFrontRegardless()

// Let the WindowServer assign a real window number.
RunLoop.current.run(until: Date().addingTimeInterval(0.2))

let wid = CGWindowID(panel.windowNumber)
line("")
line("Panel windowNumber (our own window): \(wid)")
guard wid != 0 else { line("❌ FAIL: window has no WindowServer number (no GUI session?)"); exit(3) }

// --- Determine the Space to pin to ------------------------------------------
let mainUUID = mainDisplayUUID()
let targetDisplay = topo.displays.first(where: { $0.displayIdentifier == mainUUID })
    ?? topo.displays.first
guard let spaceID = targetDisplay?.currentSpace?.id, spaceID != 0 else {
    line("❌ FAIL: could not read current Space id."); exit(4)
}
line("Target current Space id: \(spaceID)  (type \(service.spaceType(spaceID).rawValue))")

// --- The actual test: pin, then read back -----------------------------------
let before = service.spaces(ofWindow: wid)
line("Spaces before pin: \(before.sorted())")

service.move(window: wid, toExactly: spaceID)
RunLoop.current.run(until: Date().addingTimeInterval(0.3))   // let WindowServer settle

let after = service.spaces(ofWindow: wid)
line("Spaces after  pin: \(after.sorted())")

let pinned = after.contains(spaceID)
line("")
if pinned {
    line("✅ PASS 1/2 — own window pinned to current Space \(spaceID).")
} else {
    line("❌ FAIL 1/2 — pin to current Space not reflected.")
}

// --- Stronger test: relocate to a DIFFERENT (non-current) Space --------------
// This is the real proof: placing the dock on a desktop we are NOT viewing.
var crossSpaceOK = true
let otherSpaces = (targetDisplay?.spaces ?? []).filter { $0.type == .user && $0.id != spaceID }
if let other = otherSpaces.first {
    line("")
    line("Relocating dock to non-current Space \(other.id) …")
    service.move(window: wid, toExactly: other.id)
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    let moved = service.spaces(ofWindow: wid)
    line("Spaces after relocate: \(moved.sorted())")
    crossSpaceOK = moved == [other.id]   // belongs to exactly the other space, not the current one
    line(crossSpaceOK
         ? "✅ PASS 2/2 — dock now lives on Space \(other.id) only (a desktop we are not viewing)."
         : "❌ FAIL 2/2 — expected exactly [\(other.id)], got \(moved.sorted()).")

    // Restore to current Space so the interactive view shows it here.
    service.move(window: wid, toExactly: spaceID)
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
} else {
    line("(only one user Space present — skipping cross-Space relocation test)")
}

if runOnce {
    exit((pinned && crossSpaceOK) ? 0 : 1)
}

// --- Interactive mode: report live Space switches ---------------------------
line("")
line("Interactive mode. Switch desktops (Ctrl+→/←) and watch the dock + log.")
line("The blue dock should be visible ONLY on Space \(spaceID). Ctrl-C to quit.")

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
) { _ in
    let now = service.managedDisplaySpaces()
    let cur = (now.displays.first(where: { $0.displayIdentifier == mainUUID })
               ?? now.displays.first)?.currentSpace?.id ?? 0
    let here = cur == spaceID ? "  ← dock's Space (should be visible)" : "  (dock hidden here)"
    line("active Space → \(cur)\(here)")
}

app.run()
