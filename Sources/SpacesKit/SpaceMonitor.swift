import AppKit

/// Watches the system for Space and display changes and coalesces them into a
/// single debounced `onChange` callback. Purely notification-driven — there is
/// no polling — so idle CPU stays ~0% (docs/01 AC-6, docs/05 R-11).
///
/// On every relevant event it refreshes the cached `topology` snapshot, then
/// fires `onChange` on the main queue.
public final class SpaceMonitor {
    private let service: SpacesService
    public private(set) var topology: SpacesTopology

    /// Called (on main) after the topology snapshot has been refreshed.
    public var onChange: (() -> Void)?

    private var pending: DispatchWorkItem?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var defaultTokens: [NSObjectProtocol] = []
    private let debounce: TimeInterval

    public init(service: SpacesService, debounce: TimeInterval = 0.05) {
        self.service = service
        self.debounce = debounce
        self.topology = service.managedDisplaySpaces()
    }

    public func start() {
        let ws = NSWorkspace.shared.notificationCenter
        let nc = NotificationCenter.default

        workspaceTokens.append(ws.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.schedule() })

        workspaceTokens.append(ws.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.schedule() })

        defaultTokens.append(nc.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.schedule() })
    }

    public func stop() {
        let ws = NSWorkspace.shared.notificationCenter
        let nc = NotificationCenter.default
        workspaceTokens.forEach { ws.removeObserver($0) }
        defaultTokens.forEach { nc.removeObserver($0) }
        workspaceTokens.removeAll()
        defaultTokens.removeAll()
        pending?.cancel()
        pending = nil
    }

    /// Force an immediate refresh + callback (e.g. after the user edits config).
    public func refreshNow() {
        topology = service.managedDisplaySpaces()
        onChange?()
    }

    /// Current Space id for a given display (or the first display if nil/unmatched).
    public func currentSpaceID(forDisplayUUID uuid: String?) -> UInt64? {
        if let uuid, let display = topology.displays.first(where: { $0.displayIdentifier == uuid }) {
            return display.currentSpace?.id
        }
        return topology.displays.first?.currentSpace?.id
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.topology = self.service.managedDisplaySpaces()
            self.onChange?()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
