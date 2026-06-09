import AppKit
import ConfigKit

/// One interactive icon in a Dock: detects click vs drag, shows a running dot,
/// and raises context-menu/drag callbacks. Used for app/file/folder/action items
/// and for synthetic running-apps-zone entries.
public final class DockItemCell: NSView {
    /// Extra height below the icon reserved for the running-indicator dot.
    public static let dotZone: CGFloat = 10

    public let item: DockItem
    /// Index in the Dock's `items` array, or nil for dynamic zone entries.
    public let modelIndex: Int?
    public var isRunning = false { didSet { dot.isHidden = !isRunning } }

    public var onActivate: (() -> Void)?
    public var onContextMenu: ((NSEvent) -> Void)?
    public var onBeginDrag: ((DockItemCell, NSEvent) -> Void)?

    /// When true the Dock drives the icon size via `setMagnification` on cursor
    /// movement, so the cell's own hover-grow stands down to avoid fighting it.
    public var magnificationEnabled = false { didSet { if !magnificationEnabled { iconView.frame = baseIconFrame } } }

    private let iconView = NSImageView()
    private let dot = NSView()
    private var downPoint: NSPoint = .zero
    private var dragging = false
    private let iconSize: CGFloat
    private let edge: Appearance.Edge
    private var tracking: NSTrackingArea?

    public init(item: DockItem, modelIndex: Int?, iconSize: CGFloat, edge: Appearance.Edge = .bottom) {
        self.item = item
        self.modelIndex = modelIndex
        self.iconSize = iconSize
        self.edge = edge
        super.init(frame: NSRect(x: 0, y: 0, width: iconSize, height: iconSize + Self.dotZone))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: iconSize).isActive = true
        heightAnchor.constraint(equalToConstant: iconSize + Self.dotZone).isActive = true

        iconView.image = Self.image(for: item, size: iconSize)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.frame = NSRect(x: 0, y: Self.dotZone, width: iconSize, height: iconSize)
        iconView.autoresizingMask = [.width]
        addSubview(iconView)

        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.7).cgColor
        dot.layer?.cornerRadius = 2.5
        dot.frame = NSRect(x: iconSize / 2 - 2.5, y: 1, width: 5, height: 5)
        dot.isHidden = true
        addSubview(dot)

        toolTip = item.label ?? (item.path.map { ($0 as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "") })
        setAccessibilityLabel(toolTip)
    }
    required init?(coder: NSCoder) { fatalError() }

    public override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        dragging = false
    }
    public override func mouseDragged(with event: NSEvent) {
        guard item.isUserManaged, modelIndex != nil, !dragging else { return }
        let dx = event.locationInWindow.x - downPoint.x
        let dy = event.locationInWindow.y - downPoint.y
        if (dx * dx + dy * dy) > 36 {
            dragging = true
            onBeginDrag?(self, event)
        }
    }
    public override func mouseUp(with event: NSEvent) {
        if !dragging { onActivate?() }
    }
    public override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(event)
    }

    // MARK: Hover feedback

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    public override func mouseEntered(with event: NSEvent) { if !magnificationEnabled { setHovered(true) } }
    public override func mouseExited(with event: NSEvent) { if !magnificationEnabled { setHovered(false) } }

    private var baseIconFrame: NSRect { NSRect(x: 0, y: Self.dotZone, width: iconSize, height: iconSize) }

    private func setHovered(_ hovered: Bool) {
        let grow = iconSize * 0.18
        let enlarged = NSRect(x: -grow / 2, y: Self.dotZone - grow / 2,
                              width: iconSize + grow, height: iconSize + grow)
        let target = hovered ? enlarged : baseIconFrame
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            iconView.frame = target                    // respect Reduce Motion: no animation
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                iconView.animator().frame = target
            }
        }
    }

    /// Resize the icon to `iconSize * scale`, anchored against the bar so it
    /// grows *inward* (away from the screen edge) and stays centered on the
    /// Dock's length axis. Driven per cursor-move by `DockContentView`, so it
    /// is set instantly (animating each move would lag).
    public func setMagnification(_ scale: CGFloat) {
        let s = max(1, scale)
        let size = iconSize * s
        let frame: NSRect
        switch edge {
        case .bottom:                                  // grow up; bottom of icon on the bar
            frame = NSRect(x: (iconSize - size) / 2, y: Self.dotZone, width: size, height: size)
        case .top:                                     // grow down; top of icon on the bar
            frame = NSRect(x: (iconSize - size) / 2, y: Self.dotZone + iconSize - size, width: size, height: size)
        case .left:                                    // grow right; left of icon on the bar
            frame = NSRect(x: 0, y: Self.dotZone + (iconSize - size) / 2, width: size, height: size)
        case .right:                                   // grow left; right of icon on the bar
            frame = NSRect(x: iconSize - size, y: Self.dotZone + (iconSize - size) / 2, width: size, height: size)
        }
        iconView.frame = frame
    }

    static func image(for item: DockItem, size: CGFloat) -> NSImage {
        let image: NSImage
        switch item {
        case .app(let path, _), .file(let path, _):
            image = NSWorkspace.shared.icon(forFile: path)
        case .folder(let path, _, _):
            image = NSWorkspace.shared.icon(forFile: path)
        case .action(let action):
            image = NSImage(systemSymbolName: action.symbol ?? "bolt.circle.fill",
                            accessibilityDescription: action.label)
                ?? NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: nil)!
        default:
            image = NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil)!
        }
        image.size = NSSize(width: size, height: size)
        return image
    }
}
