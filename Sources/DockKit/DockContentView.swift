import AppKit
import ConfigKit

/// Renders a Dock's items as a row of cells over a frosted background, with running
/// indicators, a dynamic running-apps zone, folder-stack popovers, drag-and-drop
/// (reorder + drop-from-Finder), and per-item context menus (docs/04 §4).
public final class DockContentView: NSView {
    /// app/file/zone-app item activated.
    public var onActivateItem: ((DockItem) -> Void)?
    /// an action item fired.
    public var onRunAction: ((DockAction) -> Void)?
    /// items changed via add/remove/reorder — persist upstream.
    public var onItemsChanged: (([DockItem]) -> Void)?

    static let gap: CGFloat = 8
    static let internalType = NSPasteboard.PasteboardType("xyz.waqas.dockman.itemindex")

    private let contentHolder = NSView()
    private let stack = NSStackView()
    private var styleWrapper: NSView?
    private var items: [DockItem] = []
    private var iconSize: CGFloat = 52
    private var padding: CGFloat = CGFloat(Appearance.defaultPadding)
    private var vertical = false
    private var edge: Appearance.Edge = .bottom
    private var magnify = false
    private var folderPopover: NSPopover?
    private var magnifyTracking: NSTrackingArea?
    /// Bar-region pins for `contentHolder`, rebuilt when edge/headroom change.
    private var holderConstraints: [NSLayoutConstraint] = []

    // Track applied appearance so we only rebuild the background when it changes.
    private var appliedStyle: Appearance.Style?
    private var appliedTint: String?
    private var appliedReduceTransparency = false
    private var appliedEdge: Appearance.Edge?
    private var appliedMagnify: Bool?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        stack.orientation = .horizontal
        stack.spacing = Self.gap
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        // contentHolder lives directly on `self` (a sibling above the background
        // slab) so magnified icons can overflow the bar into the headroom without
        // being clipped by the slab's rounded-corner mask.
        contentHolder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentHolder)
        contentHolder.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentHolder.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentHolder.centerYAnchor),
        ])
        pinToBarRegion(contentHolder, headroom: 0)
        registerForDraggedTypes([.fileURL, Self.internalType])
    }

    /// Pin `view` to the bar sub-region of `self`: full length along the bar,
    /// `barThickness == self.thickness - headroom` against the screen-edge side,
    /// leaving `headroom` of transparent space on the inward side for magnified
    /// icons to grow into. headroom == 0 ⇒ fills the whole view (the non-magnified
    /// layout, byte-identical to before).
    private func pinToBarRegion(_ view: NSView, headroom: CGFloat) {
        let isHolder = (view === contentHolder)
        if isHolder { NSLayoutConstraint.deactivate(holderConstraints) }
        let c: [NSLayoutConstraint]
        switch edge {
        case .bottom:
            c = [view.leadingAnchor.constraint(equalTo: leadingAnchor),
                 view.trailingAnchor.constraint(equalTo: trailingAnchor),
                 view.bottomAnchor.constraint(equalTo: bottomAnchor),
                 view.topAnchor.constraint(equalTo: topAnchor, constant: headroom)]
        case .top:
            c = [view.leadingAnchor.constraint(equalTo: leadingAnchor),
                 view.trailingAnchor.constraint(equalTo: trailingAnchor),
                 view.topAnchor.constraint(equalTo: topAnchor),
                 view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -headroom)]
        case .left:
            c = [view.topAnchor.constraint(equalTo: topAnchor),
                 view.bottomAnchor.constraint(equalTo: bottomAnchor),
                 view.leadingAnchor.constraint(equalTo: leadingAnchor),
                 view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -headroom)]
        case .right:
            c = [view.topAnchor.constraint(equalTo: topAnchor),
                 view.bottomAnchor.constraint(equalTo: bottomAnchor),
                 view.trailingAnchor.constraint(equalTo: trailingAnchor),
                 view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: headroom)]
        }
        NSLayoutConstraint.activate(c)
        if isHolder { holderConstraints = c }
    }

    // MARK: - Background style

    private func applyStyle(_ style: Appearance.Style, tintHex: String?, headroom: CGFloat) {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        // Reduced-transparency: substitute translucent styles with a solid slab.
        let effective: Appearance.Style = (reduce && (style == .liquidGlass || style == .classic)) ? .solid : style

        styleWrapper?.removeFromSuperview()

        let tint = tintHex.flatMap { NSColor(hex: $0) }
        let radius: CGFloat = 18
        // Background-only slab. The icons live in `contentHolder`, a sibling
        // *above* this wrapper, so the wrapper's rounded-corner clipping never
        // touches a magnified icon that has grown past the bar.
        let wrapper: NSView

        switch effective {
        case .liquidGlass:
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView()
                glass.cornerRadius = radius
                glass.tintColor = tint
                glass.contentView = NSView()           // decorative slab; icons sit on top
                wrapper = glass
            } else {
                wrapper = makeVisualEffect(radius: radius)
            }
        case .classic:
            wrapper = makeVisualEffect(radius: radius)
        case .solid:
            let v = NSView(); v.wantsLayer = true
            v.layer?.backgroundColor = (tint ?? .windowBackgroundColor).withAlphaComponent(0.96).cgColor
            v.layer?.cornerRadius = radius
            v.layer?.masksToBounds = true
            wrapper = v
        case .minimal:
            wrapper = NSView()
        }

        wrapper.translatesAutoresizingMaskIntoConstraints = false
        addSubview(wrapper, positioned: .below, relativeTo: contentHolder)
        pinToBarRegion(wrapper, headroom: headroom)
        pinToBarRegion(contentHolder, headroom: headroom)
        styleWrapper = wrapper
        appliedStyle = style
        appliedTint = tintHex
        appliedReduceTransparency = reduce
        appliedEdge = edge
        appliedMagnify = magnify
    }

    private func makeVisualEffect(radius: CGFloat) -> NSVisualEffectView {
        let e = NSVisualEffectView()
        e.material = .hudWindow
        e.blendingMode = .behindWindow
        e.state = .active
        e.wantsLayer = true
        e.layer?.cornerRadius = radius
        e.layer?.masksToBounds = true
        return e
    }

    public func configure(items: [DockItem], iconSize: CGFloat, running: [RunningAppInfo],
                          vertical: Bool = false, maxLength: CGFloat = .greatestFiniteMagnitude,
                          style: Appearance.Style = .classic, tintHex: String? = nil,
                          edge: Appearance.Edge = .bottom, magnify: Bool = false,
                          padding: CGFloat = CGFloat(Appearance.defaultPadding)) {
        self.items = items
        self.iconSize = iconSize
        self.vertical = vertical
        self.edge = edge
        self.magnify = magnify
        self.padding = padding

        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let headroom = Magnifier.headroom(iconSize: iconSize, enabled: magnify)
        if style != appliedStyle || tintHex != appliedTint || reduce != appliedReduceTransparency
            || edge != appliedEdge || magnify != appliedMagnify {
            applyStyle(style, tintHex: tintHex, headroom: headroom)
        }
        updateTrackingAreas()   // install/tear down the cursor-move area as magnify toggles

        stack.orientation = vertical ? .vertical : .horizontal
        stack.alignment = vertical ? .centerX : .centerY
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let runningPaths = Set(running.compactMap { $0.bundlePath })
        let pinnedPaths = Set(items.compactMap { $0.appPath })

        // Budget so the Dock never grows past its display (docs/05 R-7). Pinned items
        // always show; the dynamic running-apps zone fills whatever room is left.
        let budget = maxLength.isFinite ? maxLength - padding * 2 : .greatestFiniteMagnitude
        let separatorLen: CGFloat = 6
        // A cell is iconSize wide but iconSize+10 tall (the running-indicator dot), so
        // its length along the stack axis differs between orientations.
        let cellLen = vertical ? iconSize + DockItemCell.dotZone : iconSize
        var used: CGFloat = 0
        func wouldFit(_ length: CGFloat) -> Bool {
            used + (used > 0 ? Self.gap : 0) + length <= budget
        }
        func consume(_ length: CGFloat) { used += (used > 0 ? Self.gap : 0) + length }

        for (index, item) in items.enumerated() {
            switch item {
            case .app, .file, .folder, .action:
                stack.addArrangedSubview(makeCell(item: item, modelIndex: index, running: runningPaths))
                consume(cellLen)
            case .separator:
                stack.addArrangedSubview(makeSeparator()); consume(separatorLen)
            case .spacer(let points):
                stack.addArrangedSubview(makeSpacer(points: CGFloat(points))); consume(CGFloat(points))
            case .runningAppsZone:
                let zoneApps = RunningZone.apps(running: running, pinnedAppPaths: pinnedPaths)
                if (!pinnedPaths.isEmpty || !zoneApps.isEmpty), wouldFit(separatorLen) {
                    stack.addArrangedSubview(makeSeparator()); consume(separatorLen)
                }
                for app in zoneApps {
                    guard let path = app.bundlePath else { continue }
                    guard wouldFit(cellLen) else { break }   // stop when out of room
                    let synthetic = DockItem.app(bundlePath: path, label: app.name)
                    let cell = makeCell(item: synthetic, modelIndex: nil, running: runningPaths)
                    cell.isRunning = true
                    stack.addArrangedSubview(cell)
                    consume(cellLen)
                }
            }
        }
    }

    public func fittingSize() -> NSSize {
        stack.layoutSubtreeIfNeeded()
        let inner = stack.fittingSize
        let minSide = iconSize + padding * 2
        var size = NSSize(width: max(inner.width + padding * 2, minSide),
                          height: max(inner.height + padding * 2, minSide))
        // Reserve room on the cross axis so the peak magnified icon clears the bar.
        let headroom = Magnifier.headroom(iconSize: iconSize, enabled: magnify)
        if vertical { size.width += headroom } else { size.height += headroom }
        return size
    }

    // MARK: - Magnification

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let magnifyTracking { removeTrackingArea(magnifyTracking) }
        magnifyTracking = nil
        guard magnify else { return }
        // .activeAlways + .mouseMoved so the non-activating Dock panel still gets
        // moves while another app is key.
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        magnifyTracking = area
    }

    public override func mouseMoved(with event: NSEvent) {
        guard magnify else { return }
        magnify(towardCursor: convert(event.locationInWindow, from: nil))
    }

    public override func mouseExited(with event: NSEvent) {
        guard magnify else { return }
        for case let cell as DockItemCell in stack.arrangedSubviews { cell.setMagnification(1) }
    }

    private func magnify(towardCursor p: NSPoint) {
        let cursor = vertical ? p.y : p.x
        let stride = iconSize + Self.gap
        for case let cell as DockItemCell in stack.arrangedSubviews {
            let f = cell.convert(cell.bounds, to: self)
            let center = vertical ? f.midY : f.midX
            cell.setMagnification(Magnifier.scale(distance: cursor - center, stride: stride))
        }
    }

    // MARK: Cell construction

    private func makeCell(item: DockItem, modelIndex: Int?, running: Set<String>) -> DockItemCell {
        let cell = DockItemCell(item: item, modelIndex: modelIndex, iconSize: iconSize, edge: edge)
        cell.magnificationEnabled = magnify
        if let path = item.path { cell.isRunning = running.contains(path) }
        cell.onActivate = { [weak self, weak cell] in
            guard let self, let cell else { return }
            self.activate(item: item, from: cell)
        }
        cell.onContextMenu = { [weak self, weak cell] event in
            guard let self, let cell else { return }
            self.showContextMenu(for: cell, event: event)
        }
        cell.onBeginDrag = { [weak self] cell, event in
            self?.beginReorderDrag(cell: cell, event: event)
        }
        return cell
    }

    private func makeSeparator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        // A horizontal stack needs a vertical separator and vice-versa.
        if vertical {
            box.widthAnchor.constraint(equalToConstant: iconSize * 0.7).isActive = true
        } else {
            box.heightAnchor.constraint(equalToConstant: iconSize * 0.7).isActive = true
        }
        return box
    }

    private func makeSpacer(points: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        if vertical {
            v.heightAnchor.constraint(equalToConstant: max(points, 1)).isActive = true
        } else {
            v.widthAnchor.constraint(equalToConstant: max(points, 1)).isActive = true
        }
        return v
    }

    // MARK: Activation

    private func activate(item: DockItem, from cell: DockItemCell) {
        switch item {
        case .folder(let path, _, let style):
            showFolderPopover(path: path, style: style, from: cell)
        case .action(let action):
            onRunAction?(action)
        default:
            onActivateItem?(item)
        }
    }

    private func showFolderPopover(path: String, style: FolderStyle, from cell: NSView) {
        folderPopover?.performClose(nil)
        let popover = NSPopover()
        popover.behavior = .transient
        let content = FolderStackView(path: path, style: style)
        content.onOpen = { [weak popover] url in
            NSWorkspace.shared.open(url)
            popover?.performClose(nil)
        }
        let vc = NSViewController()
        vc.view = content
        popover.contentViewController = vc
        content.layoutSubtreeIfNeeded()
        popover.contentSize = content.fittingSize
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: cell.bounds, of: cell, preferredEdge: .maxY)
        folderPopover = popover
    }

    // MARK: Context menu

    private func showContextMenu(for cell: DockItemCell, event: NSEvent) {
        let menu = NSMenu()
        let isZone = cell.modelIndex == nil

        switch cell.item {
        case .action:
            menu.addItem(withTitle: "Run", action: #selector(ctxOpen(_:)), keyEquivalent: "").representedObject = cell
        default:
            menu.addItem(withTitle: "Open", action: #selector(ctxOpen(_:)), keyEquivalent: "").representedObject = cell
        }
        if cell.item.path != nil {
            menu.addItem(withTitle: "Reveal in Finder", action: #selector(ctxReveal(_:)), keyEquivalent: "").representedObject = cell
        }
        menu.addItem(.separator())
        if isZone {
            menu.addItem(withTitle: "Keep in Dock", action: #selector(ctxKeep(_:)), keyEquivalent: "").representedObject = cell
        } else {
            menu.addItem(withTitle: "Remove from Dock", action: #selector(ctxRemove(_:)), keyEquivalent: "").representedObject = cell
        }
        for item in menu.items { item.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: cell)
    }

    @objc private func ctxOpen(_ sender: NSMenuItem) {
        guard let cell = sender.representedObject as? DockItemCell else { return }
        activate(item: cell.item, from: cell)
    }
    @objc private func ctxReveal(_ sender: NSMenuItem) {
        guard let cell = sender.representedObject as? DockItemCell, let path = cell.item.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
    @objc private func ctxRemove(_ sender: NSMenuItem) {
        guard let cell = sender.representedObject as? DockItemCell, let index = cell.modelIndex else { return }
        onItemsChanged?(DockItemOps.removeAt(items, index))
    }
    @objc private func ctxKeep(_ sender: NSMenuItem) {
        guard let cell = sender.representedObject as? DockItemCell else { return }
        onItemsChanged?(DockItemOps.insert(items, [cell.item], at: items.count))
    }

    // MARK: Drag & drop

    private func beginReorderDrag(cell: DockItemCell, event: NSEvent) {
        guard let index = cell.modelIndex else { return }
        let pbItem = NSPasteboardItem()
        pbItem.setString(String(index), forType: Self.internalType)
        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        let snapshot = cell.bitmapImageRepForCachingDisplay(in: cell.bounds)
        if let snapshot { cell.cacheDisplay(in: cell.bounds, to: snapshot) }
        dragItem.setDraggingFrame(cell.convert(cell.bounds, to: self),
                                  contents: snapshot.map { NSImage(cgImage: $0.cgImage!, size: cell.bounds.size) })
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.types?.contains(Self.internalType) == true ? .move : .copy
    }
    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.types?.contains(Self.internalType) == true ? .move : .copy
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let dropX = convert(sender.draggingLocation, from: nil).x
        let target = insertionIndex(atX: dropX)

        if let s = pb.string(forType: Self.internalType), let from = Int(s) {
            onItemsChanged?(DockItemOps.reorder(items, from: from, to: target))
            return true
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            let newItems = urls.map { DockItemOps.item(forDroppedPath: $0.path) }
            onItemsChanged?(DockItemOps.insert(items, newItems, at: target))
            return true
        }
        return false
    }

    /// Insertion index in `items` for a drop at view-x `x` (counts model cells to the left).
    private func insertionIndex(atX x: CGFloat) -> Int {
        var count = 0
        for view in stack.arrangedSubviews {
            guard let cell = view as? DockItemCell, cell.modelIndex != nil else { continue }
            let mid = cell.convert(cell.bounds, to: self).midX
            if x > mid { count += 1 }
        }
        return count
    }
}

extension DockContentView: NSDraggingSource {
    public func draggingSession(_ session: NSDraggingSession,
                                sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }
}
