import AppKit
import ConfigKit

/// Popover contents for a folder stack: a grid of the folder's entries; clicking
/// one opens it (docs/04 §4.2).
public final class FolderStackView: NSView {
    private let path: String
    public var onOpen: ((URL) -> Void)?

    public init(path: String, style: FolderStyle) {
        self.path = path
        super.init(frame: .zero)
        build(style: style)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build(style: FolderStyle) {
        let entries = FolderContents.entries(at: path, limit: 60)
        let cols = style == .list ? 1 : min(6, max(1, Int(Double(entries.count).squareRootRoundedUp())))
        let iconSize: CGFloat = style == .list ? 24 : 44
        let cellW: CGFloat = style == .list ? 220 : 72
        let cellH: CGFloat = style == .list ? 30 : 72
        let pad: CGFloat = 12

        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 6
        grid.columnSpacing = 6

        var row: [NSView] = []
        func flushRow() {
            while row.count < cols { row.append(NSView()) }
            grid.addRow(with: row)
            row.removeAll()
        }
        if entries.isEmpty {
            let empty = NSTextField(labelWithString: "Empty folder")
            empty.textColor = .secondaryLabelColor
            grid.addRow(with: [empty])
        } else {
            for url in entries {
                row.append(makeEntry(url: url, iconSize: iconSize, w: cellW, h: cellH, list: style == .list))
                if row.count == cols { flushRow() }
            }
            if !row.isEmpty { flushRow() }
        }

        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            grid.topAnchor.constraint(equalTo: topAnchor, constant: pad),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -pad),
        ])
    }

    private func makeEntry(url: URL, iconSize: CGFloat, w: CGFloat, h: CGFloat, list: Bool) -> NSView {
        let button = NSButton(title: url.lastPathComponent, target: self, action: #selector(open(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(url.path)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: iconSize, height: iconSize)
        button.image = icon
        button.imagePosition = list ? .imageLeading : .imageAbove
        button.bezelStyle = .smallSquare
        button.isBordered = false
        button.lineBreakMode = .byTruncatingTail
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: w).isActive = true
        button.heightAnchor.constraint(equalToConstant: h).isActive = true
        return button
    }

    @objc private func open(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        onOpen?(URL(fileURLWithPath: path))
    }
}

private extension Double {
    func squareRootRoundedUp() -> Int { Int(self.squareRoot().rounded(.up)) }
}
