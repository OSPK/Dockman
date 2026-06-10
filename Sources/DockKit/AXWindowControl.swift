import AppKit
import ApplicationServices

/// Moves another app's window onto a target display using the Accessibility API
/// (docs/09). No SIP required — just the Accessibility permission. Cannot change a
/// window's Space (that needs SIP); it repositions within the current Space, which
/// is exactly "move to the dock's monitor" under DHSS-off.
public enum AXWindowControl {

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Prompt for Accessibility permission (shows the system dialog once).
    @discardableResult
    public static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Summon an app's window to `screen`: if running, move its main window (restoring
    /// it if hidden/minimized); if it's running with *no* windows (closed via ⨯ while
    /// the app idles in the background) or not running at all, ask the system to open
    /// it — that sends the same reopen event a system-Dock click does, so the app
    /// makes a fresh window — then move that window over.
    public static func summon(appPath: String, toScreen screen: NSScreen,
                              retries: Int = 40, interval: TimeInterval = 0.15) {
        // Missing Accessibility must degrade, not swallow the click: open/activate
        // works without any permission — only the move-to-screen part needs AX.
        let trusted = isTrusted
        if !trusted { requestTrust() }

        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == appPath }) {
            if app.isHidden { app.unhide() }
            app.activate()
            if trusted {
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                if let window = mainWindow(of: appElement) {
                    _ = move(window: window, toScreen: screen)
                    return
                }
            }
            // Running but window-less (or untrusted, where we can't see windows):
            // bare activation shows nothing. Fall through to openApplication, which
            // sends the reopen event that creates/restores a window.

            // Finder is special: it's always running and its only AX window may be
            // the desktop, and being "already open" it doesn't reliably make a new
            // window on reopen. Opening a folder always does (no permission needed).
            if appPath.hasSuffix("/Finder.app") {
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
                if trusted {
                    DispatchQueue.main.async {
                        waitForWindowAndMove(pid: app.processIdentifier, screen: screen,
                                             retries: retries, interval: interval)
                    }
                }
                return
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath),
                                           configuration: configuration) { app, _ in
            guard trusted, let app else { return }
            DispatchQueue.main.async {
                waitForWindowAndMove(pid: app.processIdentifier, screen: screen,
                                     retries: retries, interval: interval)
            }
        }
    }

    @discardableResult
    public static func moveMainWindow(ofPID pid: pid_t, toScreen screen: NSScreen) -> Bool {
        guard isTrusted else { return false }
        let appElement = AXUIElementCreateApplication(pid)
        guard let window = mainWindow(of: appElement) else { return false }
        return move(window: window, toScreen: screen)
    }

    // MARK: - Pure geometry (unit-tested)

    /// Top-left position (AX/CG coordinates) to center a window of `windowSize` on a
    /// display whose Cocoa frame is `screenFrame`. `primaryMaxY` is NSMaxY of the
    /// primary (menu-bar) screen — the Cocoa↔CG flip line.
    public static func centeredTopLeft(windowSize: CGSize, screenFrame f: NSRect,
                                       primaryMaxY: CGFloat) -> CGPoint {
        let w = min(windowSize.width, f.width)
        let h = min(windowSize.height, f.height)
        let cocoaOriginX = f.midX - w / 2
        let cocoaTopY = (f.midY - h / 2) + h        // window top edge in Cocoa coords
        return CGPoint(x: cocoaOriginX, y: primaryMaxY - cocoaTopY)
    }

    // MARK: - AX plumbing

    /// Subroles that count as a summonable window. Filters out pseudo-windows —
    /// most importantly Finder's desktop, which is always present and would
    /// otherwise satisfy "the app has a window" even when none are open.
    private static let movableSubroles: Set<String> = [
        kAXStandardWindowSubrole as String,
        kAXDialogSubrole as String,
    ]

    private static func isMovableWindow(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &value) == .success,
              let subrole = value as? String else { return true }   // no subrole info → assume real
        return movableSubroles.contains(subrole)
    }

    private static func mainWindow(of appElement: AXUIElement) -> AXUIElement? {
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, attribute as CFString, &value) == .success,
               let v = value, CFGetTypeID(v) == AXUIElementGetTypeID() {
                let window = (v as! AXUIElement)
                if isMovableWindow(window) { return window }
            }
        }
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else { return nil }
        return windows.first(where: isMovableWindow)
    }

    private static func windowSize(_ window: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        AXValueGetValue(v as! AXValue, .cgSize, &size)
        return size
    }

    private static func primaryMaxY() -> CGFloat {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first
        return primary.map { NSMaxY($0.frame) } ?? 0
    }

    /// True if the window is minimized to the Dock shelf.
    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success
        else { return false }
        return (value as? Bool) == true
    }

    @discardableResult
    private static func move(window: AXUIElement, toScreen screen: NSScreen) -> Bool {
        // Restore from the Dock shelf first — repositioning a minimized window
        // succeeds but leaves it invisible, which reads as "nothing happened".
        if isMinimized(window) {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        guard let size = windowSize(window) else { return false }
        var point = centeredTopLeft(windowSize: size, screenFrame: screen.frame, primaryMaxY: primaryMaxY())
        guard let positionValue = AXValueCreate(.cgPoint, &point) else { return false }
        let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        return result == .success
    }

    private static func waitForWindowAndMove(pid: pid_t, screen: NSScreen, retries: Int, interval: TimeInterval) {
        let appElement = AXUIElementCreateApplication(pid)
        if let window = mainWindow(of: appElement),
           let size = windowSize(window), size.width > 1, size.height > 1 {
            _ = move(window: window, toScreen: screen)
            return
        }
        guard retries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            waitForWindowAndMove(pid: pid, screen: screen, retries: retries - 1, interval: interval)
        }
    }
}
