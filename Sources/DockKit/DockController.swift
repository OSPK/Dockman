import AppKit
import SpacesKit
import ConfigKit

/// Owns the on-screen windows for a single `DockModel` (one window per target
/// display) and keeps them pinned to the bound Space(s). Idempotent: `reconcile`
/// can be called on every Space/display change and converges to the desired
/// state (docs/03 §4, docs/05 R-15).
public final class DockController {
    public private(set) var model: DockModel
    private let spaces: SkyLightSpacesService

    private var windows: [String: DockPanel] = [:]        // displayUUID -> window
    private var views: [String: DockContentView] = [:]

    /// True when the bound Space(s) no longer exist and the Dock is parked on the
    /// current desktop awaiting a re-pin (docs/05 R-3, AC-4).
    public private(set) var isOrphaned = false
    /// Whether we've ever resolved this binding by an EXACT (uuid/id) match this
    /// session. Once true, a later exact miss means the Space was deleted (orphan)
    /// rather than IDs churning at login — so we stop trusting the ordinal fallback.
    private var everResolvedExact = false

    /// User edited the Dock's items via the UI (drag/drop/remove/keep). The app
    /// persists the new model and re-renders.
    public var onModelEdited: ((DockModel) -> Void)?
    /// An action item issued a dockman command (handled at app level).
    public var onActionCommand: ((DockAction) -> Void)?

    private var lastRunning: [RunningAppInfo] = []

    // Auto-hide state, per display window.
    private var revealed: [String: Bool] = [:]
    private var hideWork: [String: DispatchWorkItem] = [:]
    private let hideDelay: TimeInterval = 0.45

    public init(model: DockModel, spaces: SkyLightSpacesService) {
        self.model = model
        self.spaces = spaces
    }

    public func update(model: DockModel) {
        // A changed binding restarts the exact/ordinal heuristic.
        if model.binding != self.model.binding { everResolvedExact = false }
        self.model = model
    }

    /// Re-render items only (running indicators / zone) without re-pinning windows.
    public func refreshItems(running: [RunningAppInfo]) {
        lastRunning = running
        for (uuid, view) in views {
            let maxLen = screen(for: uuid).map { maxLength(forScreenFrame: $0.frame) } ?? .greatestFiniteMagnitude
            view.configure(items: model.items, iconSize: CGFloat(model.appearance.iconSize),
                           running: running, vertical: model.appearance.edge.isVertical, maxLength: maxLen,
                           style: model.appearance.style, tintHex: model.appearance.tintHex,
                           edge: model.appearance.edge, magnify: model.appearance.magnification,
                           magnifyScale: CGFloat(model.appearance.magnificationScale),
                           padding: CGFloat(model.appearance.padding))
        }
        resizeWindowsToFit()
    }

    /// Create/position/pin windows to match `model` against `topology`.
    public func reconcile(topology: SpacesTopology, running: [RunningAppInfo] = []) {
        lastRunning = running
        return reconcileImpl(topology: topology)
    }

    private func reconcileImpl(topology: SpacesTopology) {
        guard model.enabled else { teardown(); return }

        let targetScreens = resolveTargetScreens(NSScreen.screens)
        let targetUUIDs = Set(targetScreens.compactMap(Self.uuid(for:)))

        // Drop windows for displays we no longer target.
        for (uuid, panel) in windows where !targetUUIDs.contains(uuid) {
            spaces.unregisterOwnedWindow(CGWindowID(panel.windowNumber))
            panel.orderOut(nil)
            windows[uuid] = nil
            views[uuid] = nil
        }

        var orphanedThisPass = false
        for screen in targetScreens {
            guard let uuid = Self.uuid(for: screen) else { continue }

            let panel: DockPanel
            let view: DockContentView
            if let existingPanel = windows[uuid], let existingView = views[uuid] {
                panel = existingPanel
                view = existingView
            } else {
                panel = DockPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 80))
                view = DockContentView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
                view.autoresizingMask = [.width, .height]
                wireView(view, uuid: uuid)
                panel.contentView = view
                windows[uuid] = panel
                views[uuid] = view
            }

            view.configure(items: model.items, iconSize: CGFloat(model.appearance.iconSize),
                           running: lastRunning, vertical: model.appearance.edge.isVertical,
                           maxLength: maxLength(forScreenFrame: screen.frame),
                           style: model.appearance.style, tintHex: model.appearance.tintHex,
                           edge: model.appearance.edge, magnify: model.appearance.magnification,
                           magnifyScale: CGFloat(model.appearance.magnificationScale),
                           padding: CGFloat(model.appearance.padding))
            panel.hasShadow = model.appearance.style != .minimal
            let size = view.fittingSize()
            let revealedFrame = Self.frame(for: model.appearance, size: size, screenFrame: screen.frame)
            // Auto-hide fades the window in place (alpha + mouse-transparency) rather
            // than sliding it off-screen — robust across stacked-display layouts where
            // "below the screen" is another display, not empty space.
            panel.setFrame(revealedFrame, display: true)
            if model.behavior.autoHide {
                let shown = revealed[uuid] ?? false
                panel.alphaValue = shown ? 1 : 0
                panel.ignoresMouseEvents = !shown
            } else {
                revealed[uuid] = nil
                hideWork[uuid]?.cancel(); hideWork[uuid] = nil
                panel.alphaValue = 1
                panel.ignoresMouseEvents = false
            }

            // All-spaces docks use the public path; pinned docks omit it.
            if model.binding.mode == .allSpaces {
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            } else {
                panel.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary]
            }

            panel.orderFrontRegardless()
            let wid = CGWindowID(panel.windowNumber)
            spaces.registerOwnedWindow(wid)

            switch model.binding.mode {
            case .spaces:
                // Pin to the resolved Space(s) — own window only, SIP-safe.
                let res = BindingResolver.resolveDetailed(model.binding, topology: topology,
                                                          displayUUID: uuid,
                                                          allowOrdinal: !everResolvedExact)
                if !res.spaceIDs.isEmpty {
                    spaces.set(window: wid, spaces: res.spaceIDs)
                    if res.matchedExactly { everResolvedExact = true }
                } else if !model.binding.spaces.isEmpty {
                    // Orphaned: bound Space(s) gone. Park on the current desktop so the
                    // Dock stays usable; the menu surfaces a one-click re-pin (AC-4).
                    if let park = currentSpaceInfo(displayUUID: uuid, topology: topology)?.id {
                        spaces.move(window: wid, toExactly: park)
                    }
                    orphanedThisPass = true
                }

            case .allSpaces:
                // Visible on every desktop, but hide on fullscreen Spaces unless opted in.
                let type = currentSpaceInfo(displayUUID: uuid, topology: topology)?.type ?? .unknown
                if type == .fullscreen && !model.behavior.showOverFullscreen {
                    panel.orderOut(nil)
                } else {
                    panel.orderFrontRegardless()
                }
            }
        }
        isOrphaned = orphanedThisPass
    }

    public func teardown() {
        for (_, panel) in windows {
            spaces.unregisterOwnedWindow(CGWindowID(panel.windowNumber))
            panel.orderOut(nil)
        }
        hideWork.values.forEach { $0.cancel() }
        hideWork.removeAll()
        revealed.removeAll()
        windows.removeAll()
        views.removeAll()
        isOrphaned = false
    }

    // MARK: - Auto-hide

    /// Fed the global cursor location; fades auto-hide windows in/out by edge proximity.
    public func handleMouseMoved(_ location: NSPoint) {
        guard model.enabled, model.behavior.autoHide else { return }
        for (uuid, panel) in windows {
            guard let screen = screen(for: uuid) else { continue }
            let revealedFrame = panel.frame   // window stays put; only visibility changes
            let zone = Self.revealZone(edge: model.appearance.edge, revealed: revealedFrame, screenFrame: screen.frame)
            if revealed[uuid] == true {
                // Stay revealed while the cursor is over the Dock (or the edge strip).
                let keep = revealedFrame.insetBy(dx: -8, dy: -8).union(zone)
                if keep.contains(location) {
                    hideWork[uuid]?.cancel(); hideWork[uuid] = nil
                } else {
                    scheduleHide(uuid: uuid)
                }
            } else if zone.contains(location) {
                reveal(uuid: uuid)
            }
        }
    }

    private func reveal(uuid: String) {
        hideWork[uuid]?.cancel(); hideWork[uuid] = nil
        guard revealed[uuid] != true, let panel = windows[uuid] else { return }
        revealed[uuid] = true
        setVisible(panel, true)
    }

    private func scheduleHide(uuid: String) {
        guard revealed[uuid] == true, hideWork[uuid] == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.windows[uuid] else { return }
            self.hideWork[uuid] = nil
            guard self.model.behavior.autoHide else { return }
            self.revealed[uuid] = false
            self.setVisible(panel, false)
        }
        hideWork[uuid] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: work)
    }

    /// Fade a window in/out in place (no movement, so it never crosses to another display).
    private func setVisible(_ panel: NSPanel, _ visible: Bool) {
        panel.ignoresMouseEvents = !visible
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = visible ? 1 : 0
        }
    }

    private func screen(for uuid: String) -> NSScreen? {
        NSScreen.screens.first { Self.uuid(for: $0) == uuid }
    }

    /// The thin edge strip whose entry reveals a hidden Dock.
    static func revealZone(edge: Appearance.Edge, revealed: NSRect, screenFrame s: NSRect) -> NSRect {
        let t: CGFloat = 4
        switch edge {
        case .bottom: return NSRect(x: revealed.minX - 8, y: s.minY, width: revealed.width + 16, height: t)
        case .top:    return NSRect(x: revealed.minX - 8, y: s.maxY - t, width: revealed.width + 16, height: t)
        case .left:   return NSRect(x: s.minX, y: revealed.minY - 8, width: t, height: revealed.height + 16)
        case .right:  return NSRect(x: s.maxX - t, y: revealed.minY - 8, width: t, height: revealed.height + 16)
        }
    }

    /// Current Space on a given display, honoring DHSS topology.
    private func currentSpaceInfo(displayUUID: String, topology: SpacesTopology) -> SpaceInfo? {
        if topology.spansDisplays { return topology.displays.first?.currentSpace }
        return topology.displays.first(where: { $0.displayIdentifier == displayUUID })?.currentSpace
    }

    // MARK: - Actions

    private func wireView(_ view: DockContentView, uuid: String) {
        view.onActivateItem = { [weak self] item in self?.activate(item, fromDisplay: uuid) }
        view.onRunAction = { [weak self] action in self?.run(action) }
        view.onItemsChanged = { [weak self] items in
            guard let self else { return }
            var edited = self.model
            edited.items = items
            self.model = edited
            self.onModelEdited?(edited)        // persist upstream
            self.refreshItems(running: self.lastRunning)
        }
    }

    private func resizeWindowsToFit() {
        for (uuid, view) in views {
            guard let panel = windows[uuid],
                  let screen = NSScreen.screens.first(where: { Self.uuid(for: $0) == uuid }) else { continue }
            panel.setFrame(Self.frame(for: model.appearance, size: view.fittingSize(), screenFrame: screen.frame), display: true)
        }
    }

    private func activate(_ item: DockItem, fromDisplay uuid: String) {
        switch item {
        case .app(let path, _):
            // "Summon" mode: bring the app's window to this Dock's screen (Accessibility).
            if model.behavior.summonWindows, let screen = screen(for: uuid) {
                AXWindowControl.summon(appPath: path, toScreen: screen)
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true   // the TARGET app activates; Dockman stays an agent
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                               configuration: configuration, completionHandler: nil)
        case .file(let path, _):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        default:
            break
        }
    }

    private func run(_ action: DockAction) {
        switch action.kind {
        case .openURL:
            if let url = URL(string: action.value) { NSWorkspace.shared.open(url) }
        case .command:
            onActionCommand?(action)
        }
    }

    // MARK: - Geometry helpers

    private func resolveTargetScreens(_ screens: [NSScreen]) -> [NSScreen] {
        if model.binding.displayUUIDs.isEmpty { return screens }
        return screens.filter { screen in
            guard let uuid = Self.uuid(for: screen) else { return false }
            return model.binding.displayUUIDs.contains(uuid)
        }
    }

    public static func uuid(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let cf = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, cf) as String?
    }

    static func frame(for appearance: Appearance, size: NSSize, screenFrame f: NSRect) -> NSRect {
        let margin = CGFloat(appearance.edgeGap)
        // Never let the Dock exceed its own display, or it would spill onto an
        // adjacent one (one desktop's dock must never appear on another).
        let w = min(size.width, f.width)
        let h = min(size.height, f.height)
        var rect: NSRect
        switch appearance.edge {
        case .bottom: rect = NSRect(x: f.midX - w / 2, y: f.minY + margin, width: w, height: h)
        case .top:    rect = NSRect(x: f.midX - w / 2, y: f.maxY - margin - h, width: w, height: h)
        case .left:   rect = NSRect(x: f.minX + margin, y: f.midY - h / 2, width: w, height: h)
        case .right:  rect = NSRect(x: f.maxX - margin - w, y: f.midY - h / 2, width: w, height: h)
        }
        // Clamp fully inside the display bounds as a final safety net.
        rect.origin.x = min(max(rect.origin.x, f.minX), f.maxX - w)
        rect.origin.y = min(max(rect.origin.y, f.minY), f.maxY - h)
        return rect
    }

    /// Max Dock length (along its axis) that fits on a display, leaving edge margins.
    func maxLength(forScreenFrame f: NSRect) -> CGFloat {
        // Keep at least a small clearance on the length axis even when the dock
        // itself sits flush (edgeGap 0) against its screen edge.
        let margin = max(CGFloat(model.appearance.edgeGap), 8)
        return model.appearance.edge.isVertical ? f.height - margin * 2 : f.width - margin * 2
    }
}
