import AppKit

/// The Size column cell: a parent-relative bar (a single muted accent color, no
/// rainbow — handoff §4, rule 1) plus the formatted allocated size on the right.
/// The bar's fill fraction is `node.total / parent.total`, so it reads as
/// "share of the folder you're looking at" at every depth.
final class SizeBarView: NSView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("SizeBarView")

    private let label = NSTextField(labelWithString: "")
    private let labelWidth: CGFloat = 76
    private let gap: CGFloat = 8

    var fraction: CGFloat = 0 { didSet { needsDisplay = true } }
    var text: String = "" {
        didSet {
            label.stringValue = text
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .systemFont(ofSize: 11)
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byClipping
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: bounds.width - labelWidth, y: 0, width: labelWidth, height: bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let barMaxWidth = max(0, bounds.width - labelWidth - gap)
        let barHeight: CGFloat = 6
        let barY = (bounds.height - barHeight) / 2
        let radius = barHeight / 2

        let trackRect = NSRect(x: 0, y: barY, width: barMaxWidth, height: barHeight)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius).fill()

        let clamped = min(max(fraction, 0), 1)
        let fillWidth = barMaxWidth * clamped
        if fillWidth > 0 {
            let fillRect = NSRect(x: 0, y: barY, width: max(fillWidth, barHeight), height: barHeight)
            NSColor.controlAccentColor.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
        }
    }
}
