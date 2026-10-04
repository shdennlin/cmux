import Bonsplit
import CmuxPanes
import Foundation

extension Workspace {
    /// Brings this workspace in line with the top tabs setting. Turning it
    /// on splits panes that hold several surfaces into single-surface top
    /// tabs; no surface is closed and no process ends.
    func applyTopTabsEnabled(_ enabled: Bool) {
        guard layoutMode != .canvas, !isRemoteTmuxMirror else { return }
        if enabled {
            splitPanesIntoTopTabs()
        } else {
            moveExtraTopTabsToNewWorkspaces()
        }
        refreshTabBarVisibility()
    }

    /// Turning top tabs off: the selected tab stays, and every other tab
    /// becomes a new workspace directly below this one, keeping its splits.
    private func moveExtraTopTabsToNewWorkspaces() {
        guard topTabs.count > 1,
              let manager = owningTabManager,
              let baseIndex = manager.tabs.firstIndex(where: { $0 === self }) else { return }
        let plan = TopTabConversionPlanner.merge(
            topTabIds: topTabs.map(\.id),
            selected: selectedTopTab.id
        )
        var inserted = 0
        for tabId in plan.newWorkspaces {
            guard let tab = topTabs.first(where: { $0.id == tabId }) else { continue }
            let title = "\(self.title) · \(topTabTitle(tabId))"
            if moveTopTab(tab, toNewWorkspaceTitled: title, manager: manager, at: baseIndex + 1 + inserted) {
                inserted += 1
            }
        }
    }

    /// Rebuilds `tab`'s split tree in a new workspace, top-down: split the
    /// pane holding a node's first surface, then build each side in its own
    /// pane, so nested shapes come out the same. Returns false when the
    /// first surface could not be moved (the tab then stays put).
    private func moveTopTab(
        _ tab: WorkspaceTopTab,
        toNewWorkspaceTitled title: String,
        manager: TabManager,
        at insertionIndex: Int
    ) -> Bool {
        let tree = tab.controller.treeSnapshot()
        // Keep the last-surface handler from removing the tab mid-move.
        closingTopTabIds.insert(tab.id)
        defer { closingTopTabIds.remove(tab.id) }
        guard let firstSurface = Self.firstSurface(in: tree),
              let firstTransfer = detachTopTabSurface(firstSurface, from: tab) else { return false }
        guard let destination = manager.addWorkspace(
            fromDetachedSurface: firstTransfer,
            title: title,
            select: false,
            insertionIndexOverride: insertionIndex
        ), let rootPane = destination.activeBonsplitController.allPaneIds.first else {
            _ = tab.controller.allPaneIds.first.flatMap { attachDetachedSurface(firstTransfer, inPane: $0, focus: false) }
            return false
        }
        build(tree, in: rootPane, destination: destination, from: tab, skipping: firstSurface)
        // A surface that could not be moved stays in this tab rather than
        // being dropped with it.
        if !tab.controller.allTabIds.contains(where: { panelIdFromSurfaceId($0) != nil }) {
            removeTopTab(id: tab.id)
        }
        return true
    }

    private func build(
        _ node: ExternalTreeNode,
        in pane: PaneID,
        destination: Workspace,
        from tab: WorkspaceTopTab,
        skipping placed: TabID
    ) {
        switch node {
        case .pane(let leaf):
            for surface in Self.surfaces(in: leaf) where surface != placed {
                guard let transfer = detachTopTabSurface(surface, from: tab) else { continue }
                _ = destination.attachDetachedSurface(transfer, inPane: pane, focus: false)
            }
        case .split(let split):
            guard let secondFirst = Self.firstSurface(in: split.second),
                  let transfer = detachTopTabSurface(secondFirst, from: tab),
                  let panelId = destination.attachDetachedSurface(transfer, inPane: pane, focus: false),
                  let movingTab = destination.surfaceIdFromPanelId(panelId),
                  let secondPane = destination.splitPaneMovingTab(
                      pane,
                      orientation: SplitOrientation(rawValue: split.orientation) ?? .horizontal,
                      movingTab: movingTab,
                      insertFirst: false,
                      focusIntent: .preserveCurrent
                  ) else { return }
            build(split.first, in: pane, destination: destination, from: tab, skipping: placed)
            build(split.second, in: secondPane, destination: destination, from: tab, skipping: secondFirst)
        }
    }

    private func detachTopTabSurface(_ surface: TabID, from tab: WorkspaceTopTab) -> DetachedSurfaceTransfer? {
        guard tab.controller.allTabIds.contains(surface),
              let panelId = panelIdFromSurfaceId(surface) else { return nil }
        return detachSurface(panelId: panelId)
    }

    private static func surfaces(in leaf: ExternalPaneNode) -> [TabID] {
        leaf.tabs.compactMap { UUID(uuidString: $0.id).map { TabID(uuid: $0) } }
    }

    private static func firstSurface(in node: ExternalTreeNode) -> TabID? {
        switch node {
        case .pane(let leaf): return surfaces(in: leaf).first
        case .split(let split): return firstSurface(in: split.first) ?? firstSurface(in: split.second)
        }
    }

    /// Moves every non-selected surface of the visible layout into its own
    /// top tab, in pane (spatial) order then in-pane order.
    private func splitPanesIntoTopTabs() {
        let controller = activeBonsplitController
        let panes = controller.treeSnapshot().orderedPaneIds
            .compactMap(UUID.init(uuidString:))
            .compactMap { uuid -> TopTabPaneInput? in
                let pane = PaneID(id: uuid)
                let tabs = controller.tabs(inPane: pane)
                guard let selected = controller.selectedTab(inPane: pane)?.id ?? tabs.first?.id else {
                    return nil
                }
                return TopTabPaneInput(
                    paneId: uuid,
                    surfaceIds: tabs.map(\.id.uuid),
                    selectedSurfaceId: selected.uuid
                )
            }
        let plan = TopTabConversionPlanner.split(panesInSpatialOrder: panes)
        guard !plan.newTabs.isEmpty else { return }
        let focusedBefore = focusedPanelId
        var insertAt = (topTabs.firstIndex { $0.id == selectedTopTab.id } ?? 0) + 1
        for surface in plan.newTabs {
            let tabId = TabID(uuid: surface)
            guard let panelId = panelIdFromSurfaceId(tabId),
                  let originalPane = controller.paneId(containing: tabId),
                  let transfer = detachSurface(panelId: panelId) else { break }
            if addTopTab(adopting: transfer, select: false, at: insertAt) != nil {
                insertAt += 1
            } else {
                // Put the surface back where it was rather than lose it.
                _ = attachDetachedSurface(transfer, inPane: originalPane, focus: false)
                break
            }
        }
        if let focusedBefore, focusedPanelId != focusedBefore {
            focusPanel(focusedBefore)
        }
    }
}
