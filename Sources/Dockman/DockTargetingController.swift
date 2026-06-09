import AppKit
import DockKit

/// Hosts the targeting popover (the monitor/space picker) anchored to the status
/// item, plus the per-screen identify overlay (docs/09 §4).
final class DockTargetingController {
    private let popover = NSPopover()
    private let identify = IdentifyOverlay()
    private weak var controller: DockmanController?
    private var dockID: UUID?
    private var screenObserver: NSObjectProtocol?

    init() {
        popover.behavior = .transient
        popover.animates = true
    }

    func present(dockID: UUID, controller: DockmanController, from button: NSStatusBarButton) {
        self.controller = controller
        self.dockID = dockID
        guard let dock = controller.dock(dockID) else { return }

        // Avoid stacking observers when we re-present on a display change.
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }

        let monitors = Monitors.current()
        let topology = controller.monitor.topology
        let activeSpace = topology.displays.first?.currentSpace?.id

        let picker = MonitorSpacePicker(frame: .zero)
        picker.configure(dockName: dock.name,
                         topology: topology,
                         monitors: monitors,
                         currentBinding: dock.binding,
                         activeSpaceID: activeSpace)
        picker.setFrameSize(picker.fittingSizeForPopover())

        picker.onHoverMonitor = { [weak self] uuid in
            self?.identify.show(uuid: uuid, monitors: monitors)
        }
        picker.onCommit = { [weak self] binding in
            guard let self, let id = self.dockID else { return }
            self.controller?.setBinding(id, binding)
        }
        picker.onRequestClose = { [weak self] in self?.dismiss() }

        let vc = NSViewController()
        vc.view = picker
        popover.contentViewController = vc
        popover.contentSize = picker.fittingSizeForPopover()

        // Rebuild if the display arrangement changes while open.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self, weak button] _ in
            guard let self, let button, let id = self.dockID, self.popover.isShown else { return }
            self.present(dockID: id, controller: controller, from: button)
        }

        // Activate so the picker controls are clickable (a deliberate settings moment).
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        identify.flashAll(monitors: monitors)
    }

    private func dismiss() {
        identify.hideAll()
        popover.performClose(nil)
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
    }
}
