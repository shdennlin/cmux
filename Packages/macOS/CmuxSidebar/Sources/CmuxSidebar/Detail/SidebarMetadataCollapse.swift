/// How many metadata rows a sidebar workspace row draws, and whether it
/// offers the Show more / Show less toggle.
///
/// The sidebar row shows custom metadata in two stacks that collapse
/// independently: status entries (`set_status` / `report_meta`, collapsed
/// limit 3) and markdown blocks (`report_meta_block`, collapsed limit 1).
/// Both stacks are drawn twice — by the AppKit cell and by the legacy
/// SwiftUI row — so the limit and the toggle rule live here rather than in
/// either view.
///
/// `expandsAll` is the `sidebar.expandAllCustomMetadata` preference. It
/// renders every row and withdraws the toggle entirely, which is what a
/// caller that pushes one metadata row per agent wants: the toggle is noise
/// once every row matters.
///
/// ```swift
/// let collapse = SidebarMetadataCollapse(
///     totalCount: entries.count,
///     collapsedLimit: 3,
///     isExpanded: model.isMetadataExpanded,
///     expandsAll: model.settings.expandsAllCustomMetadata
/// )
/// let visible = collapse.visibleItems(of: entries)
/// toggleButton.isHidden = !collapse.showsToggle
/// ```
public struct SidebarMetadataCollapse: Equatable, Sendable {
    /// Status entries (`set_status` / `report_meta`) drawn while collapsed.
    public static let entryLimit = 3
    /// Markdown blocks (`report_meta_block`) drawn while collapsed.
    public static let blockLimit = 1

    /// How many of the available rows are drawn, never more than the number
    /// available.
    public let visibleCount: Int
    /// Whether the Show more / Show less toggle is drawn.
    ///
    /// `false` whenever the rows all fit within the collapsed limit, and
    /// whenever `expandsAll` made the collapsed state unreachable.
    public let showsToggle: Bool

    /// Resolves the visible row count and the toggle's presence.
    ///
    /// - Parameters:
    ///   - totalCount: Rows available to draw. Values below zero read as zero.
    ///   - collapsedLimit: Rows drawn while collapsed. Values below zero read
    ///     as zero.
    ///   - isExpanded: Whether the viewer expanded this stack. Ignored when
    ///     `expandsAll` is `true`, which is already fully expanded.
    ///   - expandsAll: The `sidebar.expandAllCustomMetadata` preference: draw
    ///     every row and withdraw the toggle.
    public init(
        totalCount: Int,
        collapsedLimit: Int,
        isExpanded: Bool,
        expandsAll: Bool
    ) {
        let total = max(0, totalCount)
        let limit = max(0, collapsedLimit)
        let overflows = total > limit
        if expandsAll {
            visibleCount = total
            showsToggle = false
        } else {
            visibleCount = isExpanded ? total : min(total, limit)
            // Matches the legacy rule: the toggle's presence depends on the
            // row count alone, so expanding never hides the way back.
            showsToggle = overflows
        }
    }

    /// Returns the leading `visibleCount` elements of `items`.
    ///
    /// - Parameter items: The rows this value was resolved for. Passing a
    ///   shorter collection is safe and yields all of it.
    /// - Returns: The rows to draw, in order.
    public func visibleItems<Element>(of items: [Element]) -> [Element] {
        guard items.count > visibleCount else { return items }
        return Array(items.prefix(visibleCount))
    }
}
