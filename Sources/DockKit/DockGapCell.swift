import AppKit
import ConfigKit

/// An interactive separator/spacer in a Dock. Unlike the synthetic divider drawn
/// before the running-apps zone, these are real model items: they can be grabbed
/// and dragged to reorder (same drag flow as icons) and right-clicked to remove.
/// A subtle capsule highlight appears on hover so they read as grabbable.
public final class DockGapCell: NSView {
    /// Length along the Dock's axis a separator occupies (wider than the hairline
    /// itself so there's something to grab).
    public static let separatorLength: CGFloat = 14

    public let item: DockItem
    public let modelIndex: Int

    public var onContextMenu: ((NSEvent) -> Void)?
    public var onBeginDrag: ((DockGapCell, NSEvent) -> Void)?

    private let highlight = NSView()
    private var downPoint: NSPoint = .zero
    private var dragging = false
    private var tracking: NSTrackingArea?

    /// `length` is the size along the Dock's axis; `cross` the perpendicular size.
    public init(item: DockItem, modelIndex: Int, length: CGFloat, cross: CGFloat, vertical: Bool) {
        self.item = item
        self.modelIndex = modelIndex
        let w = vertical ? cross : length
        let h = vertical ? length : cross
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: h))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: w).isActive = true
        heightAnchor.constraint(equalToConstant: h).isActive = true

        highlight.wantsLayer = true
        highlight.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        highlight.layer?.cornerRadius = 4
        highlight.frame = bounds.insetBy(dx: 1, dy: 1)
        highlight.autoresizingMask = [.width, .height]
        highlight.isHidden = true
        addSubview(highlight)

        if case .separator = item {
            let line = NSBox()
            line.boxType = .separator
            line.translatesAutoresizingMaskIntoConstraints = false
            addSubview(line)
            // Hairline centered in the grab area, perpendicular to the bar.
            NSLayoutConstraint.activate(vertical
                ? [line.centerYAnchor.constraint(equalTo: centerYAnchor),
                   line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                   line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2)]
                : [line.centerXAnchor.constraint(equalTo: centerXAnchor),
                   line.topAnchor.constraint(equalTo: topAnchor, constant: 2),
                   line.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)])
        }
        toolTip = {
            if case .spacer = item { return "Spacer — drag to move, right-click to remove" }
            return "Separator — drag to move, right-click to remove"
        }()
        setAccessibilityLabel(toolTip)
    }
    required init?(coder: NSCoder) { fatalError() }

    public override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        dragging = false
    }
    public override func mouseDragged(with event: NSEvent) {
        guard !dragging else { return }
        let dx = event.locationInWindow.x - downPoint.x
        let dy = event.locationInWindow.y - downPoint.y
        if (dx * dx + dy * dy) > 36 {
            dragging = true
            onBeginDrag?(self, event)
        }
    }
    public override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(event)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
    public override func mouseEntered(with event: NSEvent) { highlight.isHidden = false }
    public override func mouseExited(with event: NSEvent) { highlight.isHidden = true }
}
