import Bonsplit
import CmuxSettings
import Foundation

extension Workspace {
    /// Whether this workspace uses top tabs that each own a split layout.
    /// Canvas and remote tmux mirror workspaces keep the single-layout model.
    var isTopTabsEnabled: Bool {
        layoutMode != .canvas && !isRemoteTmuxMirror
            && settings.value(for: SettingCatalog().app.workspaceTopTabs)
    }

    var selectedTopTabId: UUID { selectedTopTab.id }

    func topTab(for controller: BonsplitController) -> WorkspaceTopTab? {
        topTabs.first { $0.controller === controller }
    }

    func topTab(containingPaneId paneId: PaneID) -> WorkspaceTopTab? {
        topTabs.first { $0.controller.allPaneIds.contains(paneId) }
    }

    func topTab(containingPanelId panelId: UUID) -> WorkspaceTopTab? {
        guard let surfaceId = surfaceIdFromPanelId(panelId) else { return nil }
        return topTabs.first { $0.controller.allTabIds.contains(surfaceId) }
    }

    func bonsplitController(containing panelId: UUID) -> BonsplitController? {
        topTab(containingPanelId: panelId)?.controller
    }

    func bonsplitController(containingPaneId paneId: PaneID) -> BonsplitController? {
        topTab(containingPaneId: paneId)?.controller
    }

    /// Makes `id` the visible top tab and re-applies its focused selection.
    func selectTopTab(id: UUID) {
        guard id != selectedTopTab.id,
              let tab = topTabs.first(where: { $0.id == id }) else { return }
        // Appearance and tab-bar updates are applied to the visible controller
        // only; every tab shares one configuration, so carry it across here.
        tab.controller.configuration = selectedTopTab.controller.configuration
        hidePortals(ofTopTab: selectedTopTab)
        selectedTopTab = tab
        didSwitchTopTab()
        if let paneId = tab.controller.focusedPaneId,
           let tabId = tab.controller.selectedTab(inPane: paneId)?.id {
            applyTabSelection(tabId: tabId, inPane: paneId)
        }
    }

    /// The configuration a new top tab starts from: the visible tab's, which
    /// already carries every appearance update applied to this workspace.
    func topTabConfiguration() -> BonsplitConfiguration {
        var configuration = activeBonsplitController.configuration
        if isTopTabsEnabled {
            configuration.tabBarVisibility = .multipleTabs
        }
        return configuration
    }

    /// Creates a top tab after the selected one, with one terminal that
    /// inherits `panelId`'s working directory.
    @discardableResult
    func addTopTab(
        select: Bool,
        inheritingDirectoryFrom panelId: UUID?,
        initialInput: String? = nil
    ) -> WorkspaceTopTab? {
        let previous = selectedTopTab
        let tab = insertEmptyTopTab()
        // Creation goes through the focused-pane path, which acts on the
        // visible controller, so the new tab is visible while it is filled.
        selectedTopTab = tab
        let welcomeTabIds = tab.controller.allTabIds
        let inheritedDirectory = panelId.flatMap { panelDirectories[$0] }
        let panel = tab.controller.allPaneIds.first.flatMap { paneId in
            newTerminalSurface(
                inPane: paneId,
                focus: select,
                workingDirectory: inheritedDirectory,
                initialInput: initialInput,
                inheritWorkingDirectoryFallback: true
            )
        }
        for welcomeTabId in welcomeTabIds {
            tab.controller.closeTab(welcomeTabId)
        }
        guard panel != nil else {
            selectedTopTab = previous
            topTabs.removeAll { $0.id == tab.id }
            return nil
        }
        // Leave the creation flip, then switch properly so the outgoing
        // tab's portals are hidden and layout follow-up runs.
        selectedTopTab = previous
        if select {
            selectTopTab(id: tab.id)
        }
        return tab
    }

    /// Moves an existing detached surface into a new top tab after the
    /// selected one. No shell is spawned: the surface keeps its process.
    @discardableResult
    func addTopTab(
        adopting transfer: DetachedSurfaceTransfer,
        select: Bool,
        at index: Int? = nil
    ) -> WorkspaceTopTab? {
        let previous = selectedTopTab
        let tab = insertEmptyTopTab(at: index)
        selectedTopTab = tab
        let welcomeTabIds = tab.controller.allTabIds
        let attached = tab.controller.allPaneIds.first.flatMap { paneId in
            attachDetachedSurface(transfer, inPane: paneId, focus: select)
        }
        for welcomeTabId in welcomeTabIds {
            tab.controller.closeTab(welcomeTabId)
        }
        guard attached != nil else {
            selectedTopTab = previous
            topTabs.removeAll { $0.id == tab.id }
            return nil
        }
        // Leave the creation flip, then switch properly so the outgoing
        // tab's portals are hidden and layout follow-up runs.
        selectedTopTab = previous
        if select {
            selectTopTab(id: tab.id)
        }
        return tab
    }

    /// Whether any panel in `topTabId` shows an unread indicator.
    func topTabHasUnread(
        _ topTabId: UUID,
        notificationStore: TerminalNotificationStore? = nil
    ) -> Bool {
        guard let tab = topTabs.first(where: { $0.id == topTabId }) else { return false }
        return tab.controller.allTabIds.contains { tabId in
            guard let panelId = panelIdFromSurfaceId(tabId) else { return false }
            return panelHasUnread(panelId, notificationStore: notificationStore)
        }
    }

    /// Whether one panel shows an unread indicator.
    func panelHasUnread(
        _ panelId: UUID,
        notificationStore: TerminalNotificationStore? = nil
    ) -> Bool {
        let notificationStore = notificationStore ?? AppDelegate.shared?.notificationStore
        return manualUnreadPanelIds.contains(panelId)
            || (notificationStore?.hasVisibleNotificationIndicator(
                forTabId: id,
                surfaceId: panelId
            ) ?? false)
    }

    /// What one panel's agent is doing, for its top tab's activity bar: the
    /// sidebar's own verdict for that pane alone, so the two never disagree on
    /// priority. Only pane-scoped status entries count. Entries are keyed per
    /// workspace, and borrowing the workspace copy would paint another pane's
    /// failure onto this one.
    func panelActivityState(
        _ panelId: UUID,
        notificationStore: TerminalNotificationStore? = nil
    ) -> TopTabActivityState? {
        // A tool that set a state owns the bar until it clears it. Its idle
        // hides the bar, except for work that finished unseen: the tool says
        // the agent is done, and the unread mark says nobody has looked.
        if let external = externalTabStates.state(for: panelId) {
            if let state = external.activityState { return state }
            return panelHasUnread(panelId, notificationStore: notificationStore) ? .done : nil
        }
        let lifecycle = (agentLifecycleStatesByPanelId[panelId] ?? [:])
            .filter { !AgentHibernationLifecycleStatusKeys.isManualKey($0.key) }
        let entries = (agentStatusEntriesByPanelId[panelId] ?? [:])
            .filter { AgentHibernationLifecycleStatusKeys.isAllowed($0.key) }
            .sorted { $0.key < $1.key }
            .map(\.value)
        let input = SidebarCompactStatusGlyph.Input(
            agentEntries: entries,
            lifecycleStates: Array(lifecycle.values),
            hasActiveAgent: SidebarAgentActivitySummary.visibleActiveCodingAgentCount(
                showsAgentActivity: true,
                statesByPanelId: [panelId: lifecycle]
            ) > 0
        )
        let kind = SidebarCompactStatusGlyph.resolve(input).kind
        if let state = TopTabActivityState(glyphKind: kind) { return state }
        // Only an agent that settled to idle can be "done". A terminal that
        // never ran one, or an agent still waiting on a wakeup, is not.
        if kind == .idle, panelHasUnread(panelId, notificationStore: notificationStore) {
            return .done
        }
        return nil
    }

    /// Shows `state` on a panel's tab, as `cmux set-tab-state` does; the last
    /// writer wins.
    ///
    /// - Returns: `false` when the panel is not in this workspace.
    @discardableResult
    func setExternalTabState(_ state: TopTabExternalState, panelId: UUID) -> Bool {
        guard panels[panelId] != nil else { return false }
        externalTabStates.set(state, for: panelId)
        return true
    }

    /// Hands a panel's tab back to cmux's own agent state.
    ///
    /// - Returns: `false` when the panel is not in this workspace.
    @discardableResult
    func clearExternalTabState(panelId: UUID) -> Bool {
        guard panels[panelId] != nil else { return false }
        externalTabStates.remove(panelId)
        return true
    }

    func externalTabState(panelId: UUID) -> TopTabExternalState? {
        externalTabStates.state(for: panelId)
    }

    func externalTabStateEntries() -> [TopTabExternalStateStore.Entry] {
        externalTabStates.entries
    }

    /// The activity bar a top tab shows: the loudest state among its panels.
    func topTabActivityState(
        _ topTabId: UUID,
        notificationStore: TerminalNotificationStore? = nil
    ) -> TopTabActivityState? {
        guard let tab = topTabs.first(where: { $0.id == topTabId }) else { return nil }
        return tab.controller.allTabIds
            .compactMap { tabId in
                panelIdFromSurfaceId(tabId).flatMap {
                    panelActivityState($0, notificationStore: notificationStore)
                }
            }
            .max { $0.urgency < $1.urgency }
    }

    /// Every pane in every top tab, the visible tab's first.
    var allTopTabPaneIds: [PaneID] {
        guard topTabs.count > 1 else { return activeBonsplitController.allPaneIds }
        let others = topTabs.filter { $0.id != selectedTopTab.id }
        return activeBonsplitController.allPaneIds + others.flatMap { $0.controller.allPaneIds }
    }

    /// The pane with `id` in any top tab, so commands that name a pane reach
    /// background tabs too.
    func paneAcrossTopTabs(id: UUID) -> PaneID? {
        allTopTabPaneIds.first { $0.id == id }
    }

    /// The controller holding `tabId`, or the visible one when no tab holds it.
    func bonsplitController(owningTab tabId: TabID) -> BonsplitController {
        guard topTabs.count > 1 else { return activeBonsplitController }
        return topTabs.first { $0.controller.allTabIds.contains(tabId) }?.controller
            ?? activeBonsplitController
    }

    /// The controller holding `paneId`, or the visible one when no tab holds it.
    func bonsplitController(owningPane paneId: PaneID) -> BonsplitController {
        guard topTabs.count > 1 else { return activeBonsplitController }
        return topTabs.first { $0.controller.allPaneIds.contains(paneId) }?.controller
            ?? activeBonsplitController
    }

    func selectNextTopTab() { selectTopTab(offset: 1) }
    func selectPreviousTopTab() { selectTopTab(offset: -1) }

    func selectTopTab(at index: Int) {
        guard topTabs.indices.contains(index) else { return }
        selectTopTab(id: topTabs[index].id)
    }

    func selectLastTopTab() {
        guard let last = topTabs.last else { return }
        selectTopTab(id: last.id)
    }

    private func selectTopTab(offset: Int) {
        guard topTabs.count > 1,
              let index = topTabs.firstIndex(where: { $0.id == selectedTopTab.id }) else { return }
        selectTopTab(id: topTabs[(index + offset + topTabs.count) % topTabs.count].id)
    }

    /// Moves the selected top tab by `offset` without wrapping.
    @discardableResult
    func moveSelectedTopTab(by offset: Int) -> Bool {
        guard let index = topTabs.firstIndex(where: { $0.id == selectedTopTab.id }) else { return false }
        let target = min(max(index + offset, 0), topTabs.count - 1)
        guard target != index else { return false }
        topTabs.insert(topTabs.remove(at: index), at: target)
        return true
    }

    /// Moving a surface into another pane would give that pane two surfaces,
    /// which the one-surface-per-pane top tab model does not allow.
    var canMoveSurfaceBetweenPanes: Bool { !isTopTabsEnabled }

    /// Closes every panel in `id` without asking, then removes the tab.
    /// The last remaining top tab is never closed this way.
    func closeTopTab(id: UUID) {
        guard topTabs.count > 1, let tab = topTabs.first(where: { $0.id == id }) else { return }
        closingTopTabIds.insert(id)
        defer { closingTopTabIds.remove(id) }
        for tabId in tab.controller.allTabIds {
            if let panelId = panelIdFromSurfaceId(tabId) {
                _ = closePanel(panelId, force: true)
            }
        }
        removeTopTab(id: id)
    }

    /// Removes an emptied top tab, selecting its right neighbour (else the
    /// left one) when it was the visible tab.
    func removeTopTab(id: UUID) {
        guard topTabs.count > 1, let index = topTabs.firstIndex(where: { $0.id == id }) else { return }
        if selectedTopTab.id == id {
            let neighbour = index + 1 < topTabs.count ? topTabs[index + 1] : topTabs[index - 1]
            selectTopTab(id: neighbour.id)
        }
        topTabs.removeAll { $0.id == id }
    }

    /// Whether closing `id` would end a running process and needs confirmation.
    func topTabNeedsCloseConfirmation(_ id: UUID) -> Bool {
        guard let tab = topTabs.first(where: { $0.id == id }) else { return false }
        return tab.controller.allTabIds.contains { tabId in
            guard let panelId = panelIdFromSurfaceId(tabId) else { return false }
            return panelNeedsConfirmClose(panelId: panelId)
        }
    }

    /// Panel ids in `id`, in pane order.
    func panelIds(inTopTab id: UUID) -> [UUID] {
        guard let tab = topTabs.first(where: { $0.id == id }) else { return [] }
        return tab.controller.allTabIds.compactMap { panelIdFromSurfaceId($0) }
    }

    /// The strip title: the custom title, else the title of the tab's
    /// focused panel.
    func topTabTitle(_ id: UUID) -> String {
        guard let tab = topTabs.first(where: { $0.id == id }) else { return "" }
        if let customTitle = tab.customTitle { return customTitle }
        let paneId = tab.controller.focusedPaneId ?? tab.controller.allPaneIds.first
        let panelId = paneId
            .flatMap { tab.controller.selectedTab(inPane: $0)?.id }
            .flatMap { panelIdFromSurfaceId($0) }
        return panelId.flatMap { panelTitle(panelId: $0) } ?? ""
    }

    /// The panel a top tab stands for: its focused pane's selected one, which
    /// also names the tab.
    private func topTabDisplayPanelId(_ id: UUID) -> UUID? {
        guard let tab = topTabs.first(where: { $0.id == id }) else { return nil }
        let paneId = tab.controller.focusedPaneId ?? tab.controller.allPaneIds.first
        return paneId
            .flatMap { tab.controller.selectedTab(inPane: $0)?.id }
            .flatMap { panelIdFromSurfaceId($0) }
    }

    /// The icon a top tab shows, as that pane's own tab bar shows it.
    func topTabIcon(_ id: UUID) -> String? {
        topTabDisplayPanelId(id).flatMap { panels[$0]?.displayIcon }
    }

    /// The agent mark a top tab shows while an agent runs in its panel; it
    /// takes the place of ``topTabIcon(_:)``, as in a pane's own tab bar.
    func topTabAgentIconAsset(_ id: UUID) -> String? {
        topTabDisplayPanelId(id).flatMap { terminalTabAgentIconAsset(forPanelId: $0) }
    }

    /// The index to give `moveTopTab(id:to:)` to drop top tab `id` into the gap
    /// before the tab at `gap` (`topTabs.count` is the gap after the last tab).
    /// Nil when that gap leaves the tab where it is, so the drop does nothing
    /// and the strip shows no insertion mark for it.
    func topTabDestinationIndex(moving id: UUID, intoGapBefore gap: Int) -> Int? {
        guard let from = topTabs.firstIndex(where: { $0.id == id }) else { return nil }
        let clamped = min(max(gap, 0), topTabs.count)
        // Taking the tab out first shifts every later gap down by one.
        let destination = clamped > from ? clamped - 1 : clamped
        return destination == from ? nil : destination
    }

    /// Sets or clears (blank `title`) a top tab's custom title.
    func renameTopTab(id: UUID, title: String) {
        guard let tab = topTabs.first(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        objectWillChange.send()
        tab.customTitle = trimmed.isEmpty ? nil : trimmed
    }

    /// Moves top tab `id` to `index` (clamped), as a drag in the strip does.
    func moveTopTab(id: UUID, to index: Int) {
        guard let from = topTabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = topTabs.remove(at: from)
        topTabs.insert(tab, at: min(max(index, 0), topTabs.count))
    }

    /// Under top tabs a pane holds one surface. When a new surface is asked
    /// for in a pane that already has one, it goes into a new top tab right
    /// after that pane's tab instead; the caller creates it in the returned
    /// tab's pane and calls finishTopTabRedirect(_:) afterwards.
    func beginTopTabRedirect(for paneId: PaneID) -> WorkspaceTopTab? {
        guard isTopTabsEnabled, topTabRedirectSuppressionDepth == 0 else { return nil }
        let controller = bonsplitController(owningPane: paneId)
        let occupied = controller.tabs(inPane: paneId).contains { panelIdFromSurfaceId($0.id) != nil }
        guard occupied else { return nil }
        let ownerIndex = topTabs.firstIndex { $0.controller === controller } ?? (topTabs.count - 1)
        return insertEmptyTopTab(at: ownerIndex + 1)
    }

    /// Drops Bonsplit's placeholder tab from a redirected top tab, or the
    /// whole tab when no surface was created in it.
    func finishTopTabRedirect(_ tab: WorkspaceTopTab?, select: Bool) {
        guard let tab else { return }
        defer {
            if select, topTabs.contains(where: { $0.id == tab.id }) {
                selectTopTab(id: tab.id)
            }
        }
        let placeholders = tab.controller.allTabIds.filter { panelIdFromSurfaceId($0) == nil }
        if placeholders.count == tab.controller.allTabIds.count {
            if selectedTopTab.id == tab.id, let first = topTabs.first(where: { $0.id != tab.id }) {
                selectTopTab(id: first.id)
            }
            topTabs.removeAll { $0.id == tab.id }
            return
        }
        placeholders.forEach { tab.controller.closeTab($0) }
    }

    /// Runs `body` with surface creation allowed to stack surfaces in a pane
    /// (session restore rebuilds panes exactly as saved).
    func withTopTabRedirectSuppressed<T>(_ body: () -> T) -> T {
        topTabRedirectSuppressionDepth += 1
        defer { topTabRedirectSuppressionDepth -= 1 }
        return body()
    }

    /// Inserts a configured top tab with Bonsplit's placeholder tab still in it.
    func insertEmptyTopTab(at index: Int? = nil) -> WorkspaceTopTab {
        let controller = Self.makeTopTabController(
            configuration: topTabConfiguration(),
            registry: tabDragTransferRegistry
        )
        configureTopTabController(controller)
        let tab = WorkspaceTopTab(controller: controller)
        let afterSelected = (topTabs.firstIndex { $0.id == selectedTopTab.id } ?? topTabs.count - 1) + 1
        topTabs.insert(tab, at: min(max(index ?? afterSelected, 0), topTabs.count))
        return tab
    }

    static func makeTopTabController(
        configuration: BonsplitConfiguration,
        registry: TabDragTransferRegistry
    ) -> BonsplitController {
        BonsplitController(configuration: configuration, tabDragTransferRegistry: registry)
    }

}
