import AppKit
import Combine
import ServiceManagement
import SpacesKit
import ConfigKit
import DockKit

/// App-level coordinator: owns the config, the SkyLight service, the Space
/// monitor, and one `DockController` per Dock. Reconciles everything on any
/// Space/display change (docs/03 §4). Observable so the SwiftUI Settings UI updates.
final class DockmanController: ObservableObject {
    let store = ConfigStore()
    @Published private(set) var config: Config
    let spaces = SkyLightSpacesService()
    let monitor: SpaceMonitor
    let activity = AppActivityMonitor()

    private var controllers: [UUID: DockController] = [:]
    private var mouseMonitors: [Any] = []
    /// Dock IDs whose bound Space was deleted and are currently parked (AC-4).
    private(set) var orphanedDockIDs: Set<UUID> = []
    /// Fired after config/topology changes so UI (status item) can refresh.
    var onStateChanged: (() -> Void)?

    init() {
        config = store.load()
        monitor = SpaceMonitor(service: spaces)
    }

    func start() {
        if config.docks.isEmpty {
            config.docks = [makeDefaultDock(name: "Dock 1")]
            try? store.save(config)
        }
        monitor.onChange = { [weak self] in self?.reconcileAll() }
        monitor.start()
        activity.onChange = { [weak self] in self?.refreshActivity() }
        activity.start()
        // Re-render when the user changes Reduce Transparency / Reduce Motion etc.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reconcileAll() }
        syncLoginItem()
        syncSystemDock()
        reconcileAll()
    }

    // MARK: - Launch at login (SMAppService)

    var isLoginItemEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Re-assert the saved preference against the actual system state on launch.
    private func syncLoginItem() {
        let status = SMAppService.mainApp.status
        NSLog("Dockman: login-item status = \(status.rawValue) (pref=\(config.global.launchAtLogin))")
        if config.global.launchAtLogin, status != .enabled {
            try? SMAppService.mainApp.register()
        } else if !config.global.launchAtLogin, status == .enabled {
            try? SMAppService.mainApp.unregister()
        }
    }

    func toggleLaunchAtLogin() {
        let enable = !isLoginItemEnabled
        do {
            if enable { try SMAppService.mainApp.register() }
            else      { try SMAppService.mainApp.unregister() }
            config.global.launchAtLogin = enable
            try? store.save(config)
        } catch {
            NSLog("Dockman: login-item toggle failed: \(error.localizedDescription)")
            // requiresApproval → point the user to System Settings.
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
        onStateChanged?()
    }

    func stop() {
        monitor.stop()
        activity.stop()
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
        mouseMonitors.removeAll()
        controllers.values.forEach { $0.teardown() }
        controllers.removeAll()
    }

    /// Running apps changed → update indicators/zone without re-pinning.
    private func refreshActivity() {
        let running = activity.snapshot()
        controllers.values.forEach { $0.refreshItems(running: running) }
    }

    // MARK: - Reconcile

    func reconcileAll() {
        let topology = monitor.topology
        let running = activity.snapshot()
        for dock in config.docks {
            let controller = controllers[dock.id] ?? makeController(for: dock)
            controller.update(model: dock)
            controller.reconcile(topology: topology, running: running)
        }
        // Tear down controllers whose dock was removed.
        for (id, controller) in controllers where !config.docks.contains(where: { $0.id == id }) {
            controller.teardown()
            controllers[id] = nil
        }
        orphanedDockIDs = Set(controllers.compactMap { $0.value.isOrphaned ? $0.key : nil })
        updateMouseMonitoring()
        onStateChanged?()
    }

    // MARK: - Auto-hide cursor tracking

    /// Run the global/local mouse monitors only while some Dock uses auto-hide.
    private func updateMouseMonitoring() {
        let needed = config.docks.contains { $0.enabled && $0.behavior.autoHide }
        if needed && mouseMonitors.isEmpty {
            let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
                self?.dispatchMouseMove()
            }
            let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                self?.dispatchMouseMove(); return event
            }
            mouseMonitors = [global, local].compactMap { $0 }
        } else if !needed {
            mouseMonitors.forEach { NSEvent.removeMonitor($0) }
            mouseMonitors.removeAll()
        }
    }

    private func dispatchMouseMove() {
        let location = NSEvent.mouseLocation
        controllers.values.forEach { $0.handleMouseMoved(location) }
    }

    // MARK: - Status-item actions

    /// A SpaceRef for the Space currently shown on the primary display.
    func currentSpaceRef() -> SpaceRef? {
        let topology = monitor.topology
        guard let display = topology.displays.first, let current = display.currentSpace else { return nil }
        let ordinal = display.spaces.firstIndex(where: { $0.id == current.id })
        return SpaceRef(spaceUUID: current.uuid,
                        spaceID: current.id,
                        displayUUID: display.displayIdentifier,
                        ordinalIndex: ordinal)
    }

    func dock(_ id: UUID) -> DockModel? { config.docks.first { $0.id == id } }

    /// Mutate a single Dock then persist + reconcile.
    private func mutate(_ id: UUID, _ change: (inout DockModel) -> Void) {
        guard let index = config.docks.firstIndex(where: { $0.id == id }) else { return }
        change(&config.docks[index])
        persistAndReconcile()
    }

    func setBinding(_ id: UUID, _ binding: Binding) { mutate(id) { $0.binding = binding } }
    func setDockAllSpaces(_ id: UUID) { mutate(id) { $0.binding = .allSpaces } }
    func setEnabled(_ id: UUID, _ on: Bool) { mutate(id) { $0.enabled = on } }
    func toggleDock(_ id: UUID) { mutate(id) { $0.enabled.toggle() } }
    func renameDock(_ id: UUID, _ name: String) { mutate(id) { $0.name = name } }
    func setAutoHide(_ id: UUID, _ on: Bool) { mutate(id) { $0.behavior.autoHide = on } }
    func setShowOverFullscreen(_ id: UUID, _ on: Bool) { mutate(id) { $0.behavior.showOverFullscreen = on } }
    func setIconSize(_ id: UUID, _ size: Double) { mutate(id) { $0.appearance.iconSize = size } }
    func setEdge(_ id: UUID, _ edge: Appearance.Edge) { mutate(id) { $0.appearance.edge = edge } }
    func setStyle(_ id: UUID, _ style: Appearance.Style) { mutate(id) { $0.appearance.style = style } }
    func setTint(_ id: UUID, _ hex: String?) { mutate(id) { $0.appearance.tintHex = hex } }
    func setMagnification(_ id: UUID, _ on: Bool) { mutate(id) { $0.appearance.magnification = on } }
    func setPadding(_ id: UUID, _ points: Double) { mutate(id) { $0.appearance.padding = points } }
    func setEdgeGap(_ id: UUID, _ points: Double) { mutate(id) { $0.appearance.edgeGap = points } }

    // Item management (Settings "Items" editor + dock context menus).
    func moveItems(_ id: UUID, from: IndexSet, to: Int) { mutate(id) { $0.items.move(fromOffsets: from, toOffset: to) } }
    func removeItems(_ id: UUID, at offsets: IndexSet) { mutate(id) { $0.items.remove(atOffsets: offsets) } }
    func appendItem(_ id: UUID, _ item: ConfigKit.DockItem) {
        mutate(id) {
            // At most one running-apps zone per dock — a second would render every
            // running app twice.
            if item == .runningAppsZone, $0.items.contains(.runningAppsZone) { return }
            $0.items.append(item)
        }
    }

    func pinDockHere(_ id: UUID) {
        guard let ref = currentSpaceRef() else { return }
        mutate(id) { $0.binding = Binding(mode: .spaces, spaces: [ref]) }
    }

    func setSummonWindows(_ id: UUID, _ on: Bool) {
        mutate(id) { $0.behavior.summonWindows = on }
        if on, !AXWindowControl.isTrusted { AXWindowControl.requestTrust() }
    }

    func newDockHere() {
        var dock = makeDefaultDock(name: "Dock \(config.docks.count + 1)")
        if let ref = currentSpaceRef() {
            dock.binding = Binding(mode: .spaces, spaces: [ref])
        }
        config.docks.append(dock)
        persistAndReconcile()
    }

    func deleteDock(_ id: UUID) {
        config.docks.removeAll { $0.id == id }
        persistAndReconcile()
    }

    // MARK: - Hide system Dock (docs/05 R-17)

    func setHideSystemDock(_ on: Bool) {
        guard config.global.hideSystemDock != on else { return }
        if on {
            config.global.priorDockAutohide = SystemDock.autohide
            SystemDock.hide()
        } else {
            SystemDock.restore(priorAutohide: config.global.priorDockAutohide ?? false)
            config.global.priorDockAutohide = nil
        }
        config.global.hideSystemDock = on
        try? store.save(config)
        onStateChanged?()
    }

    private func syncSystemDock() {
        if config.global.hideSystemDock { SystemDock.hide() }
    }

    private func persistAndReconcile() {
        try? store.save(config)
        reconcileAll()
    }

    // MARK: - Controllers & item edits

    private func makeController(for dock: DockModel) -> DockController {
        let controller = DockController(model: dock, spaces: spaces)
        let id = dock.id
        controller.onModelEdited = { [weak self] edited in self?.updateDockItems(id, edited.items) }
        controller.onActionCommand = { [weak self] action in self?.runActionCommand(action) }
        controllers[id] = controller
        return controller
    }

    /// Persist an item edit (drag/drop/remove/keep). The Dock already re-rendered;
    /// no window re-pin is required.
    func updateDockItems(_ id: UUID, _ items: [DockItem]) {
        guard let index = config.docks.firstIndex(where: { $0.id == id }) else { return }
        config.docks[index].items = items
        try? store.save(config)
        onStateChanged?()
    }

    // MARK: - Commands (URL scheme + action items)

    func handle(_ command: DockmanURL.Command) {
        switch command {
        case .toggle(let name):
            if let id = dockID(named: name) { toggleDock(id) }
        case .pin(let name):
            if let id = dockID(named: name) { pinDockHere(id) }
        case .show(let name):
            if let id = dockID(named: name), let i = index(of: id), !config.docks[i].enabled { toggleDock(id) }
        case .hide(let name):
            if let id = dockID(named: name), let i = index(of: id), config.docks[i].enabled { toggleDock(id) }
        }
    }

    private func runActionCommand(_ action: DockAction) {
        if let url = URL(string: action.value), let command = DockmanURL.parse(url) { handle(command) }
    }

    private func dockID(named name: String) -> UUID? {
        config.docks.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.id
    }
    private func index(of id: UUID) -> Int? { config.docks.firstIndex(where: { $0.id == id }) }

    // MARK: - Defaults

    private func makeDefaultDock(name: String) -> DockModel {
        let candidates = [
            "/System/Library/CoreServices/Finder.app",
            "/Applications/Safari.app",
            "/System/Applications/Notes.app",
            "/System/Applications/System Settings.app",
            "/System/Applications/Utilities/Terminal.app",
        ]
        var items: [DockItem] = candidates
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { .app(bundlePath: $0, label: nil) }
        if items.isEmpty {
            items = [.app(bundlePath: "/System/Library/CoreServices/Finder.app", label: nil)]
        }
        // Show currently-running apps (not already pinned) after a divider — like the
        // system Dock's running-apps area. This is what makes open apps appear.
        items.append(.separator)
        items.append(.runningAppsZone)

        let binding = currentSpaceRef().map { Binding(mode: .spaces, spaces: [$0]) } ?? .allSpaces
        return DockModel(id: UUID(), name: name, items: items, binding: binding)
    }
}
