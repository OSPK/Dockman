import AppKit

/// A proportional mini-map of the display arrangement (docs/09 §2). Tiles are laid
/// out by real-world position; click selects, hover reports for the identify overlay.
public final class MonitorMapView: NSView {
    public var monitors: [MonitorInfo] = [] { didSet { rebuildTracking(); needsDisplay = true } }
    public var selected: Set<String> = [] { didSet { needsDisplay = true } }
    public var multiSelect: Bool = true

    /// uuid clicked.
    public var onSelect: ((String) -> Void)?
    /// uuid hovered, or nil on exit.
    public var onHover: ((String?) -> Void)?

    private var trackingArea: NSTrackingArea?

    public override var isFlipped: Bool { false }   // y up, so the map matches reality

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Geometry

    private func unionFrame() -> NSRect {
        guard let first = monitors.first?.frame else { return .zero }
        return monitors.dropFirst().reduce(first) { $0.union($1.frame) }
    }

    private func transform() -> (scale: CGFloat, offset: CGPoint) {
        let union = unionFrame()
        guard union.width > 0, union.height > 0 else { return (1, .zero) }
        let inset: CGFloat = 14
        let avail = bounds.insetBy(dx: inset, dy: inset)
        let scale = min(avail.width / union.width, avail.height / union.height)
        let drawW = union.width * scale, drawH = union.height * scale
        let offset = CGPoint(x: bounds.midX - drawW / 2 - union.minX * scale,
                             y: bounds.midY - drawH / 2 - union.minY * scale)
        return (scale, offset)
    }

    private func tileRect(_ monitor: MonitorInfo) -> NSRect {
        let (scale, offset) = transform()
        let f = monitor.frame
        return NSRect(x: f.minX * scale + offset.x,
                      y: f.minY * scale + offset.y,
                      width: f.width * scale,
                      height: f.height * scale).insetBy(dx: 3, dy: 3)
    }

    private func monitor(at point: NSPoint) -> MonitorInfo? {
        monitors.first { tileRect($0).contains(point) }
    }

    // MARK: Drawing

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill()
        for monitor in monitors {
            let rect = tileRect(monitor)
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            let isSelected = selected.contains(monitor.uuid)
            (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.85)
                        : NSColor.tertiaryLabelColor.withAlphaComponent(0.25)).setFill()
            path.fill()
            (isSelected ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.lineWidth = isSelected ? 2 : 1
            path.stroke()

            let numColor = isSelected ? NSColor.white : NSColor.secondaryLabelColor
            drawCentered("\(monitor.ordinal)",
                         in: rect, dy: 6,
                         font: .systemFont(ofSize: min(rect.height * 0.4, 34), weight: .bold),
                         color: numColor)
            let label = monitor.isMain ? "Main" : shortName(monitor.name)
            drawCentered(label,
                         in: NSRect(x: rect.minX, y: rect.minY + 6, width: rect.width, height: 14),
                         dy: 0,
                         font: .systemFont(ofSize: 10, weight: .medium),
                         color: numColor.withAlphaComponent(0.9))
        }
    }

    private func shortName(_ name: String) -> String {
        name.count > 14 ? String(name.prefix(13)) + "…" : name
    }

    private func drawCentered(_ text: String, in rect: NSRect, dy: CGFloat, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 + dy)
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    // MARK: Interaction

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let monitor = monitor(at: point) else { return }
        if multiSelect {
            if selected.contains(monitor.uuid) { selected.remove(monitor.uuid) }
            else { selected.insert(monitor.uuid) }
        } else {
            selected = [monitor.uuid]
        }
        onSelect?(monitor.uuid)
    }

    public override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onHover?(monitor(at: point)?.uuid)
    }
    public override func mouseExited(with event: NSEvent) { onHover?(nil) }

    private func rebuildTracking() {
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        rebuildTracking()
    }
}
