import AppKit

/// The always-visible workspace number drawn before a sidebar row's title.
///
/// Uses monospaced digits so renumbering a row (closing the workspace above it
/// turns `⌃2` into `⌃1`) never changes the title's available width.
final class SidebarWorkspaceNumberLabelView: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBezeled = false
        isBordered = false
        drawsBackground = false
        usesSingleLineMode = true
        maximumNumberOfLines = 1
        lineBreakMode = .byClipping
        isHidden = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The label never takes a click: pressing it selects the row like any
    /// other part of the row.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(text: String?, fontSize: CGFloat, color: NSColor) {
        guard let text else {
            isHidden = true
            return
        }
        isHidden = false
        font = .monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        textColor = color
        if stringValue != text { stringValue = text }
    }

    /// The size the label needs for its current text, rounded up to whole points.
    var fittingLabelSize: NSSize {
        let size = intrinsicContentSize
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }
}
