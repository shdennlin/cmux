import AppKit
import Bonsplit
import CmuxAppKitSupportUI
import CmuxFoundation
import SwiftUI

/// The strip of top tabs above a workspace's split area. Each tab owns its
/// own split layout; the strip is shown only when there are two or more.
///
/// It is drawn to match Bonsplit's pane tab bar (square tabs, an accent line
/// along the selected tab's top edge, an insertion mark while dragging). Bonsplit
/// keeps its metrics and colors internal, so the values here are copies of
/// `TabBarMetrics` and `TabBarColors`; change them together.
struct WorkspaceTopTabStripView: View {
    @ObservedObject var workspace: Workspace
    /// Observed so the unread dot updates when a notification arrives.
    @EnvironmentObject var notificationStore: TerminalNotificationStore
    @State private var renamingTabId: UUID?
    @State private var renameDraft = ""
    @State private var hoveredTabId: UUID?
    /// The tab being dragged, so a drop gap that would not move it shows no mark.
    @State private var draggedTabId: UUID?
    /// The gap a drag is over (0 ... tab count), nil when none or when dropping
    /// there would leave the dragged tab where it is.
    @State private var dropGap: Int?
    @State private var tabFrames: [UUID: CGRect] = [:]
    @FocusState private var renameFieldFocused: Bool
    @Namespace private var activeIndicatorNamespace
    /// Bumped on every agent runtime change, so the agent marks (and anything
    /// else read from that runtime) redraw. The runtime is deliberately not
    /// observable, since reading it would invalidate every view that touched
    /// it on each agent event; it publishes a change stream instead.
    @State private var agentRuntimeRevision: UInt64 = 0

    private var appearance: BonsplitConfiguration.Appearance {
        workspace.activeBonsplitController.configuration.appearance
    }

    private var palette: TopTabStripPalette {
        TopTabStripPalette(appearance: appearance)
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TopTabStripStyle.tabSpacing) {
                    let _ = agentRuntimeRevision
                    ForEach(workspace.topTabs) { tab in
                        tabItem(tab)
                    }
                }
                .coordinateSpace(name: TopTabStripStyle.stripSpace)
                .onPreferenceChange(TopTabFramePreferenceKey.self) { tabFrames = $0 }
                .overlay(alignment: .topLeading) { dropIndicator }
                .onDrop(of: [.text], delegate: TopTabDropDelegate(
                    tabIds: workspace.topTabs.map(\.id),
                    frames: tabFrames,
                    draggedTabId: $draggedTabId,
                    dropGap: $dropGap,
                    destinationIndex: { id, gap in workspace.topTabDestinationIndex(moving: id, intoGapBefore: gap) },
                    onMove: { id, index in workspace.moveTopTab(id: id, to: index) }
                ))
                // The accent line slides to the newly selected tab.
                .animation(TopTabStripStyle.selectionAnimation, value: workspace.selectedTopTabId)
            }
            Button {
                workspace.addTopTab(select: true, inheritingDirectoryFrom: workspace.focusedPanelId)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 26, height: TopTabStripStyle.barHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "topTabs.newTab.help", defaultValue: "New Tab"))
            .accessibilityLabel(String(localized: "topTabs.newTab.help", defaultValue: "New Tab"))
        }
        .frame(height: TopTabStripStyle.barHeight)
        .background(palette.barBackground)
        .task(id: workspace.id) {
            for await _ in workspace.sidebarAgentRuntimeObservation.changes() {
                agentRuntimeRevision &+= 1
            }
        }
    }

    @ViewBuilder
    private var dropIndicator: some View {
        if let x = dropIndicatorX {
            Capsule()
                .fill(Color(nsColor: .controlAccentColor))
                .frame(width: TopTabStripStyle.dropIndicatorWidth, height: TopTabStripStyle.dropIndicatorHeight)
                .offset(
                    x: x - TopTabStripStyle.dropIndicatorWidth / 2,
                    y: (TopTabStripStyle.barHeight - TopTabStripStyle.dropIndicatorHeight) / 2
                )
                .allowsHitTesting(false)
        }
    }

    /// The x position of the gap a drag is over, in the strip's own space.
    private var dropIndicatorX: CGFloat? {
        guard let gap = dropGap else { return nil }
        let tabs = workspace.topTabs
        if gap < tabs.count { return tabFrames[tabs[gap].id]?.minX }
        return tabs.last.flatMap { tabFrames[$0.id]?.maxX }
    }

    @ViewBuilder
    private func tabItem(_ tab: WorkspaceTopTab) -> some View {
        let isSelected = tab.id == workspace.selectedTopTabId
        let isHovered = hoveredTabId == tab.id
        let title = workspace.topTabTitle(tab.id)
        let icon = workspace.topTabIcon(tab.id)
        let agentAsset = workspace.topTabAgentIconAsset(tab.id)
        let hasUnread = workspace.topTabHasUnread(tab.id, notificationStore: notificationStore)
        HStack(spacing: TopTabStripStyle.contentSpacing) {
            tabIcon(agentAsset: agentAsset, symbol: icon)
            if hasUnread {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            }
            if renamingTabId == tab.id {
                TextField("", text: $renameDraft)
                    .textFieldStyle(.plain)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename(tab.id) }
                    .onExitCommand { renamingTabId = nil }
                    .frame(minWidth: 60)
            } else {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button {
                close([tab.id])
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: TopTabStripStyle.closeButtonSize, height: TopTabStripStyle.closeButtonSize)
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isSelected ? 1 : 0)
            .accessibilityLabel(String(localized: "menu.file.closeTab", defaultValue: "Close Tab"))
        }
        .font(.system(size: max(appearance.tabTitleFontSize, 11)))
        .foregroundStyle(isSelected ? palette.activeText : palette.inactiveText)
        .padding(.horizontal, TopTabStripStyle.horizontalPadding)
        .frame(
            minWidth: TopTabStripStyle.tabMinWidth,
            maxWidth: TopTabStripStyle.tabMaxWidth,
            minHeight: TopTabStripStyle.barHeight,
            maxHeight: TopTabStripStyle.barHeight
        )
        .background(tabFill(isSelected: isSelected, isHovered: isHovered))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(palette.separator)
                .frame(width: 1)
        }
        .overlay(alignment: .top) {
            if isSelected {
                Rectangle()
                    .fill(Color(nsColor: .controlAccentColor))
                    .frame(height: TopTabStripStyle.activeIndicatorHeight)
                    .padding(.trailing, TopTabStripStyle.activeIndicatorTrailingInset)
                    .matchedGeometryEffect(id: "activeIndicator", in: activeIndicatorNamespace)
            }
        }
        .overlay(alignment: .bottom) {
            if let activity = workspace.topTabActivityState(tab.id, notificationStore: notificationStore) {
                WorkspaceTopTabActivityBar(state: activity)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TopTabFramePreferenceKey.self,
                    value: [tab.id: proxy.frame(in: .named(TopTabStripStyle.stripSpace))]
                )
            }
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredTabId = hovering ? tab.id : (hoveredTabId == tab.id ? nil : hoveredTabId)
            endStaleDrag()
        }
        // Select on the first click; a second click within the double-click
        // interval also starts a rename.
        .onTapGesture { workspace.selectTopTab(id: tab.id) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { beginRename(tab) })
        .overlay(MiddleClickCapture { close([tab.id]) })
        .onDrag({
            draggedTabId = tab.id
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }, preview: {
            dragPreview(title: title, agentAsset: agentAsset, icon: icon)
        })
        .contextMenu { contextMenu(for: tab) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hasUnread
            ? String(localized: "topTabs.unread.accessibility", defaultValue: "\(title), unread")
            : title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func tabFill(isSelected: Bool, isHovered: Bool) -> some View {
        if isSelected {
            Rectangle().fill(palette.selectedBackground)
        } else if isHovered {
            Rectangle().fill(palette.hoverBackground)
        } else {
            Color.clear
        }
    }

    /// The leading icon: the agent's mark while one runs in the tab, else the
    /// panel's symbol. Both sit in one square slot so titles line up.
    @ViewBuilder
    private func tabIcon(agentAsset: String?, symbol: String?) -> some View {
        if let agentAsset {
            Image(agentAsset, bundle: .main)
                .resizable()
                .scaledToFit()
                .frame(width: TopTabStripStyle.agentMarkSize, height: TopTabStripStyle.agentMarkSize)
                .frame(width: TopTabStripStyle.iconSize, height: TopTabStripStyle.iconSize)
        } else if let symbol {
            Image(systemName: symbol)
                .font(.system(size: TopTabStripStyle.iconGlyphSize))
                .frame(width: TopTabStripStyle.iconSize, height: TopTabStripStyle.iconSize)
        }
    }

    /// What follows the pointer while a tab is dragged: the tab's own look,
    /// slightly see-through, so it reads as the tab itself.
    private func dragPreview(title: String, agentAsset: String?, icon: String?) -> some View {
        HStack(spacing: TopTabStripStyle.contentSpacing) {
            tabIcon(agentAsset: agentAsset, symbol: icon)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: max(appearance.tabTitleFontSize, 11)))
        .foregroundStyle(palette.activeText)
        .padding(.horizontal, TopTabStripStyle.horizontalPadding)
        .frame(height: TopTabStripStyle.barHeight)
        .background(palette.selectedBackground)
        .opacity(0.85)
    }

    @ViewBuilder
    private func contextMenu(for tab: WorkspaceTopTab) -> some View {
        Button(String(localized: "topTabs.menu.rename", defaultValue: "Rename Tab…")) {
            beginRename(tab)
        }
        Divider()
        Button(String(localized: "menu.file.closeTab", defaultValue: "Close Tab")) {
            close([tab.id])
        }
        Button(String(localized: "topTabs.menu.closeOthers", defaultValue: "Close Other Tabs")) {
            close(workspace.topTabs.map(\.id).filter { $0 != tab.id })
        }
        .disabled(workspace.topTabs.count < 2)
        Button(String(localized: "topTabs.menu.closeRight", defaultValue: "Close Tabs to the Right")) {
            guard let index = workspace.topTabs.firstIndex(where: { $0.id == tab.id }) else { return }
            close(workspace.topTabs.suffix(from: index + 1).map(\.id))
        }
        .disabled(workspace.topTabs.last?.id == tab.id)
    }

    private func close(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        if let manager = workspace.owningTabManager {
            manager.closeTopTabsWithConfirmation(ids, in: workspace)
        } else {
            ids.forEach { workspace.closeTopTab(id: $0) }
        }
    }

    /// A drag cancelled with Esc, or released outside the strip, never reaches
    /// the drop delegate, so it leaves its insertion mark and dragged tab
    /// behind. Hover events do not arrive while the button is held during a
    /// drag, so one arriving with the button up means no drag is going on.
    private func endStaleDrag() {
        guard dropGap != nil || draggedTabId != nil,
              NSEvent.pressedMouseButtons & 1 == 0 else { return }
        dropGap = nil
        draggedTabId = nil
    }

    private func beginRename(_ tab: WorkspaceTopTab) {
        renameDraft = workspace.topTabTitle(tab.id)
        renamingTabId = tab.id
        renameFieldFocused = true
    }

    private func commitRename(_ id: UUID) {
        workspace.renameTopTab(id: id, title: renameDraft)
        renamingTabId = nil
    }
}

/// Copies of Bonsplit's `TabBarMetrics` (the values noted beside each).
private struct TopTabStripStyle {
    static let stripSpace = "workspaceTopTabStrip"
    static let barHeight: CGFloat = 30            // TabBarMetrics.barHeight
    static let tabSpacing: CGFloat = 0            // TabBarMetrics.tabSpacing
    static let tabMinWidth: CGFloat = 90          // wider than TabBarMetrics.tabMinWidth (48), kept from before
    static let tabMaxWidth: CGFloat = 220         // TabBarMetrics.tabMaxWidth
    static let horizontalPadding: CGFloat = 6     // TabBarMetrics.tabHorizontalPadding
    static let contentSpacing: CGFloat = 6        // TabBarMetrics.contentSpacing
    static let iconSize: CGFloat = 14             // TabBarMetrics.iconSize
    static let iconGlyphSize: CGFloat = 11
    static let agentMarkSize: CGFloat = 11.5      // max(10, TabBarMetrics.iconSize - 2.5)
    static let closeButtonSize: CGFloat = 16      // TabBarMetrics.closeButtonSize
    static let activeIndicatorHeight: CGFloat = 1.5   // TabBarMetrics.activeIndicatorHeight
    static let activeIndicatorTrailingInset: CGFloat = 1   // TabBarMetrics.activeIndicatorTrailingInset
    static let dropIndicatorWidth: CGFloat = 2    // TabBarMetrics.dropIndicatorWidth
    static let dropIndicatorHeight: CGFloat = 20  // TabBarMetrics.dropIndicatorHeight
    static let selectionAnimation = Animation.easeInOut(duration: 0.15)   // TabBarMetrics.selectionDuration
}

/// Copies of Bonsplit's `TabBarColors` for the tab fills, separator and text,
/// resolved from the same chrome colors in the same order, so the strip reads
/// like the pane tab bars beside it.
private struct TopTabStripPalette {
    /// What the strip paints behind its tabs. Bonsplit's own bar is clear when
    /// the window shares one backdrop, because the pane draws the theme color
    /// under it; the strip sits outside any pane, so it paints that color itself.
    let barBackground: Color
    let selectedBackground: Color
    let hoverBackground: Color
    let separator: Color
    let activeText: Color
    let inactiveText: Color

    init(appearance: BonsplitConfiguration.Appearance) {
        let colors = appearance.chromeColors
        let chromeBackground = colors.backgroundHex.flatMap { NSColor(topTabChromeHex: $0) }
        // The tab bar's own color, else the chrome's, as Bonsplit resolves it.
        let custom = colors.tabBarBackgroundHex.flatMap { NSColor(topTabChromeHex: $0) } ?? chromeBackground
        // Text and the shared-backdrop tint go by the first color that is not clear.
        let semantic = custom.flatMap(Self.nonClear) ?? chromeBackground.flatMap(Self.nonClear)
        barBackground = Color(nsColor: semantic ?? .windowBackgroundColor)

        if let semantic {
            // Light bar -> dark text, and the other way round.
            let darkText = semantic.topTabIsLight
            let base = darkText ? NSColor.black : NSColor.white
            activeText = Color(nsColor: base.withAlphaComponent(0.82))
            inactiveText = Color(nsColor: base.withAlphaComponent(darkText ? 0.62 : 0.68))
        } else {
            activeText = Color(nsColor: .labelColor)
            inactiveText = Color(nsColor: .secondaryLabelColor)
        }

        guard let custom else {
            selectedBackground = Color(nsColor: .controlBackgroundColor)
            hoverBackground = Color(nsColor: .controlBackgroundColor).opacity(0.5)
            separator = Color(nsColor: colors.borderHex.flatMap { NSColor(topTabChromeHex: $0) } ?? .separatorColor)
            return
        }
        let isLight = custom.topTabIsLight
        if appearance.usesSharedBackdrop {
            // The host paints one backdrop under the bar and the tabs, so a tab
            // is only a tint over it.
            selectedBackground = .clear
            let tintIsDark = (semantic ?? custom).topTabIsLight
            hoverBackground = Color(nsColor: tintIsDark
                ? NSColor.black.withAlphaComponent(0.055)
                : NSColor.white.withAlphaComponent(0.075))
        } else {
            selectedBackground = Color(nsColor: isLight
                ? custom.topTabDarkened(by: 0.065)
                : custom.topTabLightened(by: 0.12))
            hoverBackground = Color(nsColor: (isLight
                ? custom.topTabDarkened(by: 0.03)
                : custom.topTabLightened(by: 0.07)).withAlphaComponent(0.78))
        }
        if let border = colors.borderHex.flatMap({ NSColor(topTabChromeHex: $0) }) {
            separator = Color(nsColor: border)
        } else {
            separator = Color(nsColor: (isLight
                ? custom.topTabDarkened(by: 0.12)
                : custom.topTabLightened(by: 0.16)).withAlphaComponent(isLight ? 0.26 : 0.36))
        }
    }

    private static func nonClear(_ color: NSColor) -> NSColor? {
        let resolved = color.usingColorSpace(.sRGB) ?? color
        return resolved.alphaComponent <= 0.001 ? nil : resolved
    }
}

private extension NSColor {
    /// A chrome color as the app hands it to Bonsplit: `#RRGGBB` or `#RRGGBBAA`.
    /// The shared `NSColor(hex:)` takes six digits and drops alpha, so it would
    /// read every translucent chrome color, such as the clear tab bar color a
    /// shared backdrop sets, as missing.
    convenience init?(topTabChromeHex value: String) {
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8,
              hex.allSatisfy(\.isHexDigit),
              let rgba = UInt64(hex, radix: 16) else { return nil }
        if hex.count == 8 {
            self.init(
                red: CGFloat((rgba & 0xFF00_0000) >> 24) / 255,
                green: CGFloat((rgba & 0x00FF_0000) >> 16) / 255,
                blue: CGFloat((rgba & 0x0000_FF00) >> 8) / 255,
                alpha: CGFloat(rgba & 0x0000_00FF) / 255
            )
        } else {
            self.init(
                red: CGFloat((rgba & 0xFF0000) >> 16) / 255,
                green: CGFloat((rgba & 0x00FF00) >> 8) / 255,
                blue: CGFloat(rgba & 0x0000FF) / 255,
                alpha: 1
            )
        }
    }

    var topTabIsLight: Bool {
        let color = usingColorSpace(.sRGB) ?? self
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linearized(_ component: CGFloat) -> CGFloat {
            component <= 0.03928
                ? component / 12.92
                : CGFloat(pow(Double((component + 0.055) / 1.055), 2.4))
        }
        let luminance = 0.2126 * linearized(red) + 0.7152 * linearized(green) + 0.0722 * linearized(blue)
        // Light when black text contrasts with it more than white text does.
        return (luminance + 0.05) / 0.05 > 1.05 / (luminance + 0.05)
    }

    func topTabLightened(by amount: CGFloat) -> NSColor {
        shiftedChannels(by: amount)
    }

    func topTabDarkened(by amount: CGFloat) -> NSColor {
        shiftedChannels(by: -amount)
    }

    private func shiftedChannels(by amount: CGFloat) -> NSColor {
        let color = usingColorSpace(.sRGB) ?? self
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func shifted(_ component: CGFloat) -> CGFloat { min(1, max(0, component + amount)) }
        return NSColor(red: shifted(red), green: shifted(green), blue: shifted(blue), alpha: alpha)
    }
}

/// Each tab's frame in the strip's space, so the insertion mark and the drop
/// gap can be placed from where the tabs are.
private struct TopTabFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Finds the gap between tabs a dragged tab is over, shows it as the insertion
/// mark, and moves the tab there on drop.
private struct TopTabDropDelegate: DropDelegate {
    let tabIds: [UUID]
    let frames: [UUID: CGRect]
    @Binding var draggedTabId: UUID?
    @Binding var dropGap: Int?
    /// Where the tab ends up for a gap, or nil when that gap leaves it in place.
    let destinationIndex: (UUID, Int) -> Int?
    let onMove: (UUID, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedTabId != nil && tabIds.count > 1
    }

    func dropEntered(info: DropInfo) {
        updateDropGap(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropGap(for: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        dropGap = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedTabId = nil
            dropGap = nil
        }
        guard let draggedTabId,
              let destination = destinationIndex(draggedTabId, gap(at: info.location)) else { return false }
        onMove(draggedTabId, destination)
        return true
    }

    private func updateDropGap(for info: DropInfo) {
        let gap = gap(at: info.location)
        let next: Int?
        if let draggedTabId, destinationIndex(draggedTabId, gap) == nil {
            next = nil
        } else {
            next = gap
        }
        guard dropGap != next else { return }
        dropGap = next
    }

    /// The gap before the first tab whose middle is right of the pointer, or
    /// the one after the last tab.
    private func gap(at point: CGPoint) -> Int {
        tabIds.firstIndex { id in
            guard let frame = frames[id] else { return false }
            return frame.midX > point.x
        } ?? tabIds.count
    }
}
