import AppKit
import ConfigKit
import SpacesKit

/// The targeting surface hosted in the status-item popover (docs/09 §4). Adapts to
/// the DHSS topology: DHSS-off = multi-select monitors × one shared desktop strip;
/// DHSS-on = single monitor (master) → its desktops (detail).
public final class MonitorSpacePicker: NSView {
    public var onCommit: ((Binding) -> Void)?
    public var onHoverMonitor: ((String?) -> Void)?
    public var onRequestClose: (() -> Void)?

    private var dockName = ""
    private var topology = SpacesTopology(displays: [], spansDisplays: false)
    private var monitors: [MonitorInfo] = []
    private var activeSpaceID: UInt64?
    private var dhssOff: Bool { topology.spansDisplays }

    // Selection state
    private var selectedMonitors: Set<String> = []
    private var selectedSpaceID: UInt64?
    private var allDesktops = false

    // Views
    private let titleLabel = NSTextField(labelWithString: "")
    private let explainer = NSTextField(wrappingLabelWithString: "")
    private let currentLabel = NSTextField(labelWithString: "")
    private let monitorHeader = NSTextField(labelWithString: "")
    private let map = MonitorMapView()
    private let desktopHeader = NSTextField(labelWithString: "Desktop")
    private let spaceStrip = NSStackView()
    private let allDesktopsCheck = NSButton(checkboxWithTitle: "Show on all desktops", target: nil, action: nil)
    private let pinHereButton = NSButton(title: "Pin to Current Desktop", target: nil, action: nil)
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)

    public static let width: CGFloat = 380

    public override var isFlipped: Bool { true }   // top-down layout

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViews()
    }
    required init?(coder: NSCoder) { fatalError() }

    public func configure(dockName: String, topology: SpacesTopology, monitors: [MonitorInfo],
                          currentBinding: Binding, activeSpaceID: UInt64?) {
        self.dockName = dockName
        self.topology = topology
        self.monitors = monitors
        self.activeSpaceID = activeSpaceID

        // Seed selection from the current binding.
        allDesktops = currentBinding.mode == .allSpaces
        if currentBinding.displayUUIDs.isEmpty {
            selectedMonitors = Set(monitors.map(\.uuid))     // empty == all
        } else {
            selectedMonitors = Set(currentBinding.displayUUIDs)
        }
        if dhssOff {
            map.multiSelect = true
        } else {
            map.multiSelect = false
            // DHSS-on: collapse to a single master monitor.
            if let first = selectedMonitors.first { selectedMonitors = [first] }
            else if let main = monitors.first(where: { $0.isMain })?.uuid { selectedMonitors = [main] }
        }
        // Seed selected desktop.
        let masterUUID = dhssOff ? nil : selectedMonitors.first
        let spaces = DockTargeting.userSpaces(topology: topology, monitorUUID: masterUUID)
        if let refID = currentBinding.spaces.first?.spaceID, spaces.contains(where: { $0.id == refID }) {
            selectedSpaceID = refID
        } else {
            selectedSpaceID = activeSpaceID ?? spaces.first?.id
        }
        rebuild()
    }

    /// Computed popover size.
    public func fittingSizeForPopover() -> NSSize {
        let mapH: CGFloat = monitors.count > 1 ? 150 : 0
        let height: CGFloat = 20 + 22 + 44 + 22 + 14 + mapH + (mapH > 0 ? 16 : 0) + 18 + 48 + 22 + 40 + 20
        return NSSize(width: Self.width, height: height)
    }

    // MARK: Build

    private func buildViews() {
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        explainer.font = .systemFont(ofSize: 11)
        explainer.textColor = .secondaryLabelColor
        explainer.preferredMaxLayoutWidth = Self.width - 32
        currentLabel.font = .systemFont(ofSize: 11)
        currentLabel.textColor = .secondaryLabelColor
        monitorHeader.font = .systemFont(ofSize: 11, weight: .medium)
        monitorHeader.textColor = .secondaryLabelColor
        desktopHeader.font = .systemFont(ofSize: 11, weight: .medium)
        desktopHeader.textColor = .secondaryLabelColor

        spaceStrip.orientation = .horizontal
        spaceStrip.spacing = 6
        spaceStrip.alignment = .centerY

        map.onSelect = { [weak self] uuid in self?.monitorSelected(uuid) }
        map.onHover = { [weak self] uuid in self?.onHoverMonitor?(uuid) }

        allDesktopsCheck.target = self
        allDesktopsCheck.action = #selector(toggleAllDesktops)
        pinHereButton.target = self
        pinHereButton.action = #selector(pinHere)
        pinHereButton.bezelStyle = .rounded
        doneButton.target = self
        doneButton.action = #selector(done)
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"

        for v in [titleLabel, explainer, currentLabel, monitorHeader, map, desktopHeader,
                  spaceStrip, allDesktopsCheck, pinHereButton, doneButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = true
            addSubview(v)
        }
    }

    // MARK: Layout + content refresh

    private func rebuild() {
        let pad: CGFloat = 16
        var y: CGFloat = 14
        let w = Self.width - pad * 2

        titleLabel.stringValue = "Move “\(dockName)”"
        titleLabel.frame = NSRect(x: pad, y: y, width: w, height: 20); y += 24

        explainer.stringValue = dhssOff
            ? "Desktops span all monitors. Pick a desktop, then the monitors to show on."
            : "Each monitor has its own desktops. Pick a monitor, then its desktop."
        explainer.frame = NSRect(x: pad, y: y, width: w, height: 30); y += 34

        currentLabel.stringValue = currentBindingSummary()
        currentLabel.frame = NSRect(x: pad, y: y, width: w, height: 16); y += 22

        if monitors.count > 1 {
            monitorHeader.isHidden = false
            map.isHidden = false
            monitorHeader.stringValue = dhssOff ? "Show on these monitors" : "Monitor"
            monitorHeader.frame = NSRect(x: pad, y: y, width: w, height: 14); y += 18
            map.monitors = monitors
            map.multiSelect = dhssOff
            map.selected = selectedMonitors
            map.frame = NSRect(x: pad, y: y, width: w, height: 150); y += 166
        } else {
            monitorHeader.isHidden = true
            map.isHidden = true
        }

        desktopHeader.frame = NSRect(x: pad, y: y, width: w, height: 14); y += 18
        rebuildSpaceStrip()
        spaceStrip.frame = NSRect(x: pad, y: y, width: w, height: 44); y += 52

        allDesktopsCheck.state = allDesktops ? .on : .off
        allDesktopsCheck.frame = NSRect(x: pad, y: y, width: w, height: 20); y += 30

        pinHereButton.sizeToFit()
        doneButton.sizeToFit()
        let doneW: CGFloat = 80
        let pinW = max(pinHereButton.frame.width + 24, 170)
        pinHereButton.frame = NSRect(x: pad, y: y, width: pinW, height: 28)
        doneButton.frame = NSRect(x: Self.width - pad - doneW, y: y, width: doneW, height: 28)

        // Desktop selection is meaningless when "all desktops" is on.
        spaceStrip.subviews.forEach { ($0 as? NSButton)?.isEnabled = !allDesktops }
    }

    private func rebuildSpaceStrip() {
        spaceStrip.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let masterUUID = dhssOff ? nil : selectedMonitors.first
        let spaces = DockTargeting.userSpaces(topology: topology, monitorUUID: masterUUID)
        for (index, space) in spaces.enumerated() {
            let isCurrent = space.id == activeSpaceID
            let title = "\(index + 1)" + (isCurrent ? "•" : "")
            let tile = NSButton(title: title, target: self, action: #selector(spaceTapped(_:)))
            tile.bezelStyle = .smallSquare
            tile.setButtonType(.toggle)
            tile.state = space.id == selectedSpaceID ? .on : .off
            tile.tag = Int(bitPattern: UInt(space.id))
            tile.toolTip = isCurrent ? "Desktop \(index + 1) (current)" : "Desktop \(index + 1)"
            tile.translatesAutoresizingMaskIntoConstraints = false
            tile.widthAnchor.constraint(equalToConstant: 40).isActive = true
            tile.heightAnchor.constraint(equalToConstant: 40).isActive = true
            spaceStrip.addArrangedSubview(tile)
        }
        if spaces.isEmpty {
            let none = NSTextField(labelWithString: "No desktops found")
            none.font = .systemFont(ofSize: 11)
            none.textColor = .tertiaryLabelColor
            spaceStrip.addArrangedSubview(none)
        }
    }

    private func currentBindingSummary() -> String {
        let mons = selectedMonitors.isEmpty ? "no monitors"
            : monitors.filter { selectedMonitors.contains($0.uuid) }
                      .sorted { $0.ordinal < $1.ordinal }
                      .map { "\($0.ordinal)" }.joined(separator: "")
        if allDesktops { return "Target: all desktops · Monitors \(mons)" }
        let spaces = DockTargeting.userSpaces(topology: topology, monitorUUID: dhssOff ? nil : selectedMonitors.first)
        let deskNum = (spaces.firstIndex { $0.id == selectedSpaceID }).map { $0 + 1 }
        let desk = deskNum.map { "Desktop \($0)" } ?? "—"
        return "Target: \(desk) · Monitors \(mons)"
    }

    // MARK: Actions

    private func monitorSelected(_ uuid: String) {
        if dhssOff {
            // multiSelect mutated by the map; mirror it.
            selectedMonitors = map.selected
        } else {
            selectedMonitors = [uuid]
            map.selected = selectedMonitors
            // Master changed → its desktop list changed; reseed selected desktop.
            let spaces = DockTargeting.userSpaces(topology: topology, monitorUUID: uuid)
            if !spaces.contains(where: { $0.id == selectedSpaceID }) {
                selectedSpaceID = spaces.first(where: { $0.id == activeSpaceID })?.id ?? spaces.first?.id
            }
        }
        rebuild()
        commit()
    }

    @objc private func spaceTapped(_ sender: NSButton) {
        let id = UInt64(UInt(bitPattern: sender.tag))
        selectedSpaceID = id
        allDesktops = false
        // single-select within the strip
        spaceStrip.subviews.compactMap { $0 as? NSButton }.forEach { $0.state = ($0 === sender) ? .on : .off }
        allDesktopsCheck.state = .off
        currentLabel.stringValue = currentBindingSummary()
        commit()
    }

    @objc private func toggleAllDesktops() {
        allDesktops = allDesktopsCheck.state == .on
        spaceStrip.subviews.forEach { ($0 as? NSButton)?.isEnabled = !allDesktops }
        currentLabel.stringValue = currentBindingSummary()
        commit()
    }

    @objc private func pinHere() {
        allDesktops = false
        if let id = activeSpaceID { selectedSpaceID = id }
        rebuild()
        commit()
    }

    @objc private func done() { onRequestClose?() }

    private func commit() {
        let masterUUID = dhssOff ? nil : selectedMonitors.first
        let spaces = DockTargeting.userSpaces(topology: topology, monitorUUID: masterUUID)
        let space = spaces.first { $0.id == selectedSpaceID }
        let ordinal = spaces.firstIndex { $0.id == selectedSpaceID }
        // Empty == all monitors; if every monitor is selected, normalize to empty.
        let displayUUIDs: [String] = selectedMonitors.count == monitors.count ? [] : Array(selectedMonitors)
        let binding = DockTargeting.binding(allDesktops: allDesktops,
                                            space: space,
                                            ordinal: ordinal,
                                            displayUUIDs: displayUUIDs,
                                            dhssOff: dhssOff)
        onCommit?(binding)
    }
}
