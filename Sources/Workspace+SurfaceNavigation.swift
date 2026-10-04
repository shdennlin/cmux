import Bonsplit
import CmuxPanes
import CmuxWorkspaces
import Foundation

/// Surface navigation and sidebar status helpers extracted from `Workspace.swift`, which sits at its file-length budget.
extension Workspace {
    /// Synchronizes a nested remote-tmux pane with its outer workspace pane
    /// without reactivating an already-selected container's hidden surface.
    func focusRemoteTmuxContainerPaneIfNeeded(_ paneId: PaneID) {
        guard activeBonsplitController.focusedPaneId != paneId else { return }
        bonsplitController(owningPane: paneId).focusPane(paneId)
    }

    /// Moves keyboard focus through the rendered pane hierarchy. A selected
    /// remote-tmux window owns a nested split tree, so it gets first refusal;
    /// an edge with no inner neighbor falls through to the workspace tree.
    @discardableResult
    func moveFocus(direction: NavigationDirection) -> Bool {
        if layoutMode == .canvas {
            return moveCanvasFocus(direction: direction)
        }
        if let focusedPanelId,
           let mirror = remoteTmuxWindowMirror(forPanelId: focusedPanelId) {
            switch mirror.navigateFocus(direction: direction) {
            case .moved:
                return true
            case .invalid:
                return false
            case .edge:
                break
            }
        }

        let previousFocusedPanelId = focusedPanelId
        let previousFocusedPaneId = activeBonsplitController.focusedPaneId
        if let previousFocusedPanelId, let previous = panels[previousFocusedPanelId] {
            previous.unfocus()
        }

        activeBonsplitController.navigateFocus(direction: direction)
        if let paneId = activeBonsplitController.focusedPaneId,
           let tabId = bonsplitController(owningPane: paneId).selectedTab(inPane: paneId)?.id {
            applyTabSelection(tabId: tabId, inPane: paneId)
        }
        return previousFocusedPanelId != focusedPanelId ||
            previousFocusedPaneId != activeBonsplitController.focusedPaneId
    }

    /// Moves the focused surface into another pane, optionally creating a
    /// directional split when no adjacent pane exists.
    @discardableResult
    func moveFocusedSurface(
        to movement: SurfacePaneMovement,
        allowMissingDestinationSplit: Bool = true
    ) -> Bool {
        guard canMoveSurfaceBetweenPanes else { return false }
        guard let panelId = focusedPanelId else { return false }
        return moveSurface(
            panelId: panelId,
            to: movement,
            allowMissingDestinationSplit: allowMissingDestinationSplit
        )
    }

    /// Moves a surface through the same ownership-transfer path used by
    /// same-workspace drag and drop.
    @discardableResult
    func moveSurface(
        panelId: UUID,
        to movement: SurfacePaneMovement,
        allowMissingDestinationSplit: Bool = true
    ) -> Bool {
        guard layoutMode != .canvas,
              !isRemoteTmuxMirror,
              panels[panelId] != nil,
              let sourcePaneId = paneId(forPanelId: panelId) else {
            return false
        }

        let destinationPaneId = destinationPane(
            from: sourcePaneId,
            for: movement
        )
        let directionalSplit = allowMissingDestinationSplit
            ? directionalSplit(for: movement)
            : nil
        guard destinationPaneId != nil || directionalSplit != nil else {
            return false
        }

        let zoomedPaneId = activeBonsplitController.zoomedPaneId
        if zoomedPaneId != nil {
            clearSplitZoom()
        }

        let didMove: Bool
        if let destinationPaneId {
            didMove = moveSurface(
                panelId: panelId,
                toPane: destinationPaneId,
                atIndex: insertionIndexAfterSelectedSurface(in: destinationPaneId),
                focus: true
            )
        } else if let directionalSplit,
                  let tabId = surfaceIdFromPanelId(panelId),
                  let newPaneId = splitPaneMovingTab(
                      sourcePaneId,
                      orientation: directionalSplit.orientation,
                      movingTab: tabId,
                      insertFirst: directionalSplit.insertFirst,
                      focusIntent: .activateMovedTab
                  ) {
            bonsplitController(owningPane: newPaneId).focusPane(newPaneId)
            bonsplitController(owningTab: tabId).selectTab(tabId)
            focusPanel(panelId)
            didMove = true
        } else {
            didMove = false
        }

        if !didMove, let zoomedPaneId {
            _ = bonsplitController(owningPane: zoomedPaneId).togglePaneZoom(inPane: zoomedPaneId)
        }
        return didMove
    }

    private func destinationPane(
        from sourcePaneId: PaneID,
        for movement: SurfacePaneMovement
    ) -> PaneID? {
        if let direction = directionalSplit(for: movement)?.direction {
            return activeBonsplitController.adjacentPane(
                to: sourcePaneId,
                direction: direction
            )
        }

        let orderedPaneIds = spatiallyOrderedPaneIds
        guard orderedPaneIds.count > 1,
              let sourceIndex = orderedPaneIds.firstIndex(of: sourcePaneId.id) else {
            return nil
        }
        let offset = movement == .previous ? -1 : 1
        let destinationIndex = (
            sourceIndex + offset + orderedPaneIds.count
        ) % orderedPaneIds.count
        let destinationID = orderedPaneIds[destinationIndex]
        return activeBonsplitController.allPaneIds.first { $0.id == destinationID }
    }

    private func directionalSplit(
        for movement: SurfacePaneMovement
    ) -> (
        direction: NavigationDirection,
        orientation: SplitOrientation,
        insertFirst: Bool
    )? {
        switch movement {
        case .left: (.left, .horizontal, true)
        case .right: (.right, .horizontal, false)
        case .up: (.up, .vertical, true)
        case .down: (.down, .vertical, false)
        case .previous, .next: nil
        }
    }

    private func insertionIndexAfterSelectedSurface(in paneId: PaneID) -> Int {
        let destinationTabs = bonsplitController(owningPane: paneId).tabs(inPane: paneId)
        guard let selectedTabId = bonsplitController(owningPane: paneId).selectedTab(inPane: paneId)?.id,
              let selectedIndex = destinationTabs.firstIndex(where: {
                  $0.id == selectedTabId
              }) else {
            return destinationTabs.count
        }
        return selectedIndex + 1
    }

    /// Notification unread lookup for sidebar surface indicators.
    func hasUnreadNotification(panelId: UUID) -> Bool {
        AppDelegate.shared?.notificationStore?.hasUnreadNotification(forTabId: id, surfaceId: panelId) ?? false
    }

    /// Surface-kind mapping used by workspace state snapshots.
    func surfaceKind(for panel: any Panel) -> String {
        Self.surfaceKind(for: panel.panelType)
    }

    /// Surface-kind mapping used by snapshots and mobile mapping parity tests.
    static func surfaceKind(for panelType: PanelType) -> String {
        switch panelType {
        case .terminal:
            return SurfaceKind.terminal.rawValue
        case .browser:
            return SurfaceKind.browser.rawValue
        case .markdown:
            return SurfaceKind.markdown.rawValue
        case .filePreview:
            return SurfaceKind.filePreview.rawValue
        case .rightSidebarTool:
            return SurfaceKind.rightSidebarTool.rawValue
        case .customSidebar:
            return SurfaceKind.customSidebar.rawValue
        case .simulator:
            return SurfaceKind.simulator.rawValue
        case .agentSession:
            return SurfaceKind.agentSession.rawValue
        case .project:
            return SurfaceKind.project.rawValue
        case .extensionBrowser:
            return SurfaceKind.extensionBrowser.rawValue
        case .workspaceTodo:
            return SurfaceKind.todo.rawValue
        case .coderouterGuide:
            return SurfaceKind.coderouterGuide.rawValue
        case .notifications:
            return SurfaceKind.notifications.rawValue
        case .cloudVMLoading:
            return SurfaceKind.cloudVMLoading.rawValue
        case .mobilePairing:
            return SurfaceKind.mobilePairing.rawValue
        case .accountSignIn:
            return SurfaceKind.accountSignIn.rawValue
        case .cloudVPNSetup:
            return SurfaceKind.cloudVPNSetup.rawValue
        }
    }

    /// Select the next surface in the currently focused split pane, or in
    /// workspace Canvas order when Canvas layout is active.
    func selectNextSurface() {
        if isTopTabsEnabled {
            selectNextTopTab()
            return
        }
        if layoutMode == .canvas {
            _ = selectAdjacentCanvasTab(offset: 1)
            return
        }
        activeBonsplitController.selectNextTab()

        if let paneId = activeBonsplitController.focusedPaneId,
           let tabId = bonsplitController(owningPane: paneId).selectedTab(inPane: paneId)?.id {
            applyTabSelection(tabId: tabId, inPane: paneId)
        }
    }

    /// Select the previous surface in the currently focused split pane, or in
    /// workspace Canvas order when Canvas layout is active.
    func selectPreviousSurface() {
        if isTopTabsEnabled {
            selectPreviousTopTab()
            return
        }
        if layoutMode == .canvas {
            _ = selectAdjacentCanvasTab(offset: -1)
            return
        }
        activeBonsplitController.selectPreviousTab()

        if let paneId = activeBonsplitController.focusedPaneId,
           let tabId = bonsplitController(owningPane: paneId).selectedTab(inPane: paneId)?.id {
            applyTabSelection(tabId: tabId, inPane: paneId)
        }
    }

    /// Previous/Next inside the focused pane (Canvas: the workspace's surfaces) when it holds two
    /// or more tabs, wrapping there. False when there is nothing to step, so the keys move between
    /// workspaces instead (``TabManager/stepTabOrWorkspace(forward:dock:)``).
    func stepFocusedPaneTab(forward: Bool) -> Bool {
        if layoutMode == .canvas { return selectAdjacentCanvasTab(offset: forward ? 1 : -1) }
        guard let paneId = activeBonsplitController.focusedPaneId,
              activeBonsplitController.tabs(inPane: paneId).count > 1 else { return false }
        if forward { selectNextSurface() } else { selectPreviousSurface() }
        return true
    }

    /// Cycles focus to the next or previous split pane in tree order, wrapping at the ends.
    @discardableResult
    func cycleFocus(forward: Bool) -> Bool {
        guard layoutMode != .canvas else { return false }

        guard let targetPaneId = PaneCycleNavigator().targetPane(
            orderedPaneIds: spatiallyOrderedPaneIds,
            livePaneIds: activeBonsplitController.allPaneIds,
            focusedPaneId: activeBonsplitController.focusedPaneId,
            forward: forward
        ) else { return false }

        if let previousPanelId = focusedPanelId,
           let previousPanel = panels[previousPanelId] {
            previousPanel.unfocus()
        }

        bonsplitController(owningPane: targetPaneId).focusPane(targetPaneId)

        if let paneId = activeBonsplitController.focusedPaneId,
           let tabId = bonsplitController(owningPane: paneId).selectedTab(inPane: paneId)?.id {
            applyTabSelection(tabId: tabId, inPane: paneId)
        }
        return true
    }

    /// Moves the selected surface within its focused split or Canvas pane
    /// without wrapping.
    @discardableResult
    func moveSelectedSurface(by offset: Int) -> Bool {
        if isTopTabsEnabled {
            return moveSelectedTopTab(by: offset)
        }
        if layoutMode == .canvas {
            guard let focusedPanelId else { return false }
            return reorderSurface(panelId: focusedPanelId, by: offset)
        }
        guard let paneId = activeBonsplitController.focusedPaneId,
              let selectedTab = bonsplitController(owningPane: paneId).selectedTab(inPane: paneId),
              let panelId = panelIdFromSurfaceId(selectedTab.id) else { return false }
        return reorderSurface(panelId: panelId, by: offset)
    }

    /// Reorders one surface by a relative final-position offset in the
    /// current layout's authoritative tab model.
    @discardableResult
    func reorderSurface(panelId: UUID, by offset: Int) -> Bool {
        if layoutMode == .canvas {
            let previousRevision = canvasModel.revision
            guard canvasModel.reorderPanel(panelId, by: offset) else { return false }
            if canvasModel.revision != previousRevision {
                canvasModel.viewport?.modelDidChangeExternally(animated: false)
            }
            return true
        }
        guard let paneId = paneId(forPanelId: panelId),
              let tabId = surfaceIdFromPanelId(panelId) else { return false }
        let tabs = bonsplitController(owningPane: paneId).tabs(inPane: paneId)
        guard let currentIndex = tabs.firstIndex(where: { $0.id == tabId }), !tabs.isEmpty else { return false }
        let finalIndex = min(max(currentIndex + offset, tabs.startIndex), tabs.index(before: tabs.endIndex))
        guard finalIndex != currentIndex else { return true }
        let insertionIndex = finalIndex > currentIndex ? finalIndex + 1 : finalIndex
        return reorderSurface(panelId: panelId, toIndex: insertionIndex)
    }

    /// Select a surface by index in the currently focused split pane, or in
    /// workspace Canvas order when Canvas layout is active.
    func selectSurface(at index: Int) {
        if isTopTabsEnabled {
            selectTopTab(at: index)
            return
        }
        if layoutMode == .canvas {
            _ = selectCanvasTab(at: index)
            return
        }
        guard let focusedPaneId = activeBonsplitController.focusedPaneId else { return }
        let tabs = bonsplitController(owningPane: focusedPaneId).tabs(inPane: focusedPaneId)
        guard tabs.indices.contains(index) else { return }
        activeBonsplitController.selectTab(tabs[index].id)

        if let tabId = bonsplitController(owningPane: focusedPaneId).selectedTab(inPane: focusedPaneId)?.id {
            applyTabSelection(tabId: tabId, inPane: focusedPaneId)
        }
    }

    /// Select the last surface in the currently focused split pane, or in
    /// workspace Canvas order when Canvas layout is active.
    func selectLastSurface() {
        if isTopTabsEnabled {
            selectLastTopTab()
            return
        }
        if layoutMode == .canvas {
            _ = selectLastCanvasTab()
            return
        }
        guard let focusedPaneId = activeBonsplitController.focusedPaneId else { return }
        let tabs = bonsplitController(owningPane: focusedPaneId).tabs(inPane: focusedPaneId)
        guard let last = tabs.last else { return }
        bonsplitController(owningTab: last.id).selectTab(last.id)

        if let tabId = bonsplitController(owningPane: focusedPaneId).selectedTab(inPane: focusedPaneId)?.id {
            applyTabSelection(tabId: tabId, inPane: focusedPaneId)
        }
    }
}
