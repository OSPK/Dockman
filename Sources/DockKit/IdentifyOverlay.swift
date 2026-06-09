import AppKit

/// Shows a large number on each physical display so the user can map a tile in the
/// monitor mini-map to the actual screen (docs/09 §2, cue 2). Click-through so it
/// never interferes with the picker.
public final class IdentifyOverlay {
    private var windows: [String: NSWindow] = [:]   // monitor uuid -> overlay window
    private var hideWork: DispatchWorkItem?
    private var hoveredUUID: String?

    public init() {}

    /// Flash every monitor's number briefly (on picker open).
    public func flashAll(monitors: [MonitorInfo], duration: TimeInterval = 1.2) {
        for monitor in monitors { showWindow(for: monitor) }
        scheduleHide(after: duration)
    }

    /// Keep one monitor's number visible (on hover). nil ⇒ hide all (unless flashing).
    public func show(uuid: String?, monitors: [MonitorInfo]) {
        hideWork?.cancel()
        hoveredUUID = uuid
        if let uuid, let monitor = monitors.first(where: { $0.uuid == uuid }) {
            // Hide non-hovered, show the hovered one.
            for (key, win) in windows where key != uuid { win.orderOut(nil) }
            showWindow(for: monitor)
        } else {
            hideAll()
        }
    }

    public func hideAll() {
        hideWork?.cancel()
        hoveredUUID = nil
        windows.values.forEach { $0.orderOut(nil) }
    }

    private func scheduleHide(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Don't hide a monitor the user is currently hovering.
            for (uuid, win) in self.windows where uuid != self.hoveredUUID { win.orderOut(nil) }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func showWindow(for monitor: MonitorInfo) {
        let win = windows[monitor.uuid] ?? makeWindow(for: monitor)
        windows[monitor.uuid] = win
        // Re-center in case the display moved/resized.
        let side: CGFloat = 220
        let rect = NSRect(x: monitor.frame.midX - side / 2,
                          y: monitor.frame.midY - side / 2,
                          width: side, height: side)
        win.setFrame(rect, display: true)
        win.orderFrontRegardless()
    }

    private func makeWindow(for monitor: MonitorInfo) -> NSWindow {
        let win = NSPanel(contentRect: .zero,
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true                 // click-through
        win.level = .screenSaver
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        badge.layer?.cornerRadius = 28
        badge.translatesAutoresizingMaskIntoConstraints = false

        let number = NSTextField(labelWithString: "\(monitor.ordinal)")
        number.font = .systemFont(ofSize: 120, weight: .bold)
        number.textColor = .white
        number.alignment = .center
        number.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: monitor.isMain ? "\(monitor.name) (Main)" : monitor.name)
        name.font = .systemFont(ofSize: 15, weight: .medium)
        name.textColor = .white
        name.alignment = .center
        name.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(badge)
        badge.addSubview(number)
        badge.addSubview(name)
        win.contentView = content

        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 200),
            badge.heightAnchor.constraint(equalToConstant: 200),
            number.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            number.centerYAnchor.constraint(equalTo: badge.centerYAnchor, constant: -14),
            name.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            name.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -22),
            name.leadingAnchor.constraint(greaterThanOrEqualTo: badge.leadingAnchor, constant: 8),
            name.trailingAnchor.constraint(lessThanOrEqualTo: badge.trailingAnchor, constant: -8),
        ])
        return win
    }
}
