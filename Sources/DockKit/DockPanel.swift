import AppKit

/// The borderless, non-activating window that hosts a Dock's contents.
/// Clicking items never makes Dockman the active app (docs/02 §3.1, docs/05 R-6).
public final class DockPanel: NSPanel {
    public init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Sit at the system Dock's window level by default.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        // Space membership is managed explicitly via SkyLight in pinned mode, so
        // we deliberately omit .canJoinAllSpaces here (the controller adds it only
        // for all-spaces docks).
        collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
