import AppKit

/// The Name column cell: an SF Symbol icon, the entry name, and — for online-only
/// cloud placeholders — a trailing cloud badge (handoff §4, rule 4). The disclosure
/// triangle and indentation are supplied by `NSOutlineView` itself.
final class NameCellView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("NameCellView")

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let cloud = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        title.lineBreakMode = .byTruncatingMiddle
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        cloud.setContentHuggingPriority(.required, for: .horizontal)
        cloud.image = NSImage(systemSymbolName: "icloud", accessibilityDescription: "Cloud placeholder")
        cloud.contentTintColor = .secondaryLabelColor

        let stack = NSStackView(views: [icon, title, cloud])
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        textField = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(name: String, isDirectory: Bool, isDataless: Bool) {
        title.stringValue = name
        icon.image = NSImage(
            systemSymbolName: isDirectory ? "folder.fill" : "doc",
            accessibilityDescription: nil)
        icon.contentTintColor = isDirectory ? .controlAccentColor : .secondaryLabelColor
        cloud.isHidden = !isDataless
    }
}
