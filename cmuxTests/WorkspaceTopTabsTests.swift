import Bonsplit
import CmuxSettings
import Foundation
import Testing
#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite(.serialized)
struct WorkspaceTopTabsTests {
    @Test func newWorkspaceHasOneTopTabWhoseControllerIsActive() throws {
        let workspace = Workspace()
        #expect(workspace.topTabs.count == 1)
        #expect(workspace.activeBonsplitController === workspace.topTabs[0].controller)
        #expect(workspace.selectedTopTabId == workspace.topTabs[0].id)
    }

    @Test func addTopTabCreatesIsolatedLayoutAndKeepsPanelsWorkspaceWide() throws {
        let workspace = Workspace()
        let firstPanel = try #require(workspace.focusedTerminalPanel)
        let second = try #require(workspace.addTopTab(select: true, inheritingDirectoryFrom: firstPanel.id))
        #expect(workspace.topTabs.count == 2)
        #expect(workspace.activeBonsplitController === second.controller)
        #expect(second.controller.allPaneIds.count == 1)
        #expect(second.controller.allTabIds.count == 1)
        let secondPanelId = try #require(workspace.focusedTerminalPanel?.id)
        #expect(secondPanelId != firstPanel.id)
        #expect(workspace.panels[firstPanel.id] != nil)
        #expect(workspace.panels[secondPanelId] != nil)
        #expect(workspace.topTab(containingPanelId: firstPanel.id)?.id == workspace.topTabs[0].id)
        #expect(workspace.bonsplitController(containing: secondPanelId) === second.controller)
    }

    @Test func addTopTabWithoutSelectingKeepsTheVisibleTab() throws {
        let workspace = Workspace()
        let firstPanel = try #require(workspace.focusedTerminalPanel)
        let first = workspace.topTabs[0]
        let second = try #require(workspace.addTopTab(select: false, inheritingDirectoryFrom: firstPanel.id))
        #expect(workspace.selectedTopTabId == first.id)
        #expect(second.controller.allTabIds.count == 1)
        #expect(workspace.focusedTerminalPanel?.id == firstPanel.id)
    }

    @Test func splitInSelectedTabDoesNotTouchOtherTab() throws {
        let workspace = Workspace()
        let firstPanel = try #require(workspace.focusedTerminalPanel)
        let first = workspace.topTabs[0]
        _ = try #require(workspace.addTopTab(select: true, inheritingDirectoryFrom: firstPanel.id))
        let secondPanelId = try #require(workspace.focusedTerminalPanel?.id)
        _ = workspace.newTerminalSplit(from: secondPanelId, orientation: .horizontal)
        #expect(workspace.activeBonsplitController.allPaneIds.count == 2)
        #expect(first.controller.allPaneIds.count == 1)
    }

    @Test func eventFromBackgroundTabDoesNotChangeSelection() throws {
        let workspace = Workspace()
        let firstPanel = try #require(workspace.focusedTerminalPanel)
        let first = workspace.topTabs[0]
        let second = try #require(workspace.addTopTab(select: true, inheritingDirectoryFrom: firstPanel.id))
        let pane = try #require(first.controller.allPaneIds.first)
        first.controller.focusPane(pane)
        #expect(workspace.selectedTopTabId == second.id)
    }

    @Test func selectTopTabSwitchesTheActiveController() throws {
        let workspace = Workspace()
        let firstPanel = try #require(workspace.focusedTerminalPanel)
        let first = workspace.topTabs[0]
        _ = try #require(workspace.addTopTab(select: true, inheritingDirectoryFrom: firstPanel.id))
        workspace.selectTopTab(id: first.id)
        #expect(workspace.activeBonsplitController === first.controller)
        #expect(workspace.focusedTerminalPanel?.id == firstPanel.id)
    }

    // MARK: id-based operations resolve the owning top tab (Task 4a)

    @Test func closingPanelInBackgroundTabClosesItThere() throws {
        let workspace = Workspace()
        let firstPanel = try #require(workspace.focusedTerminalPanel)
        let first = workspace.topTabs[0]
        let splitPanel = try #require(workspace.newTerminalSplit(from: firstPanel.id, orientation: .horizontal))
        let second = try #require(workspace.addTopTab(select: true, inheritingDirectoryFrom: firstPanel.id))
        #expect(first.controller.allPaneIds.count == 2)
        #expect(workspace.closePanel(splitPanel.id, force: true))
        #expect(first.controller.allPaneIds.count == 1)
        #expect(second.controller.allPaneIds.count == 1)
        #expect(workspace.selectedTopTabId == second.id)
        #expect(workspace.panels[splitPanel.id] == nil)
    }

    @Test func focusingPanelInBackgroundTabSelectsThatTab() throws {
        let workspace = Workspace()
        let firstPanel = try #require(workspace.focusedTerminalPanel)
        let first = workspace.topTabs[0]
        _ = try #require(workspace.addTopTab(select: true, inheritingDirectoryFrom: firstPanel.id))
        workspace.focusPanel(firstPanel.id)
        #expect(workspace.selectedTopTabId == first.id)
        #expect(workspace.focusedPanelId == firstPanel.id)
    }

    @Test func unreadInBackgroundTabMarksThatTabWithoutSwitching() throws {
        let workspace = Workspace()
        let backgroundPanel = try #require(workspace.focusedTerminalPanel)
        let second = try #require(workspace.addTopTab(select: true, inheritingDirectoryFrom: backgroundPanel.id))
        workspace.markPanelUnread(backgroundPanel.id)
        #expect(workspace.selectedTopTabId == second.id)
        #expect(workspace.topTabHasUnread(workspace.topTabs[0].id))
        #expect(!workspace.topTabHasUnread(second.id))
    }

    @Test func adoptingDetachedSurfaceMovesItIntoANewTabWithoutSpawning() throws {
        let workspace = Workspace()
        let firstPanel = try #require(workspace.focusedTerminalPanel)
        let movingPanel = try #require(workspace.newTerminalSplit(from: firstPanel.id, orientation: .horizontal))
        let panelCount = workspace.panels.count
        let transfer = try #require(workspace.detachSurface(panelId: movingPanel.id))
        let tab = try #require(workspace.addTopTab(adopting: transfer, select: false))
        #expect(workspace.panels.count == panelCount)
        #expect(workspace.topTab(containingPanelId: movingPanel.id)?.id == tab.id)
        #expect(tab.controller.allTabIds.count == 1)
        #expect(workspace.selectedTopTabId == workspace.topTabs[0].id)
    }

    // MARK: socket and CLI lookups see every top tab (Task 4b)

    @Test func paneLookupByIdFindsAPaneInABackgroundTab() throws {
        let workspace = Workspace()
        let firstPanel = try #require(workspace.focusedTerminalPanel)
        let backgroundPane = try #require(workspace.topTabs[0].controller.allPaneIds.first)
        let second = try #require(workspace.addTopTab(select: true, inheritingDirectoryFrom: firstPanel.id))
        #expect(workspace.paneAcrossTopTabs(id: backgroundPane.id) == backgroundPane)
        #expect(workspace.allTopTabPaneIds.count == 2)
        #expect(workspace.bonsplitController(owningPane: backgroundPane) === workspace.topTabs[0].controller)
        #expect(workspace.selectedTopTabId == second.id)
    }

    // MARK: whole-tree readers see every top tab (Task 4c)

    @Test func treeReadersListPanesAndSurfacesFromEveryTopTab() throws {
        let workspace = Workspace()
        let backgroundPanel = try #require(workspace.focusedTerminalPanel)
        let backgroundPane = try #require(workspace.topTabs[0].controller.allPaneIds.first)
        _ = try #require(workspace.addTopTab(select: true, inheritingDirectoryFrom: backgroundPanel.id))
        let visiblePanelId = try #require(workspace.focusedTerminalPanel?.id)
        #expect(workspace.allPaneIds.count == 2)
        #expect(workspace.paneId(forPanelId: backgroundPanel.id) == backgroundPane)
        #expect(workspace.selectedSurfaceId(inPaneId: backgroundPane.id) != nil)
        let ordered = workspace.surfaceList.orderedPanelIds
        #expect(ordered.first == visiblePanelId)
        #expect(ordered.contains(backgroundPanel.id))
        #expect(workspace.spatiallyOrderedPaneIds.count == 1)
    }

    // MARK: a top tab shows the agent running in its panel

    @Test func topTabShowsTheAgentMarkOfItsOwnPanel() throws {
        let workspace = Workspace()
        let backgroundPanel = try #require(workspace.focusedTerminalPanel)
        let backgroundTab = workspace.topTabs[0]
        let visibleTab = try #require(workspace.addTopTab(select: true, inheritingDirectoryFrom: backgroundPanel.id))
        let expectedAsset = try #require(TerminalTabAgentIconResolver().assetName(forStatusKey: "claude_code"))
        #expect(workspace.topTabAgentIconAsset(backgroundTab.id) == nil)
        #expect(workspace.topTabAgentIconAsset(visibleTab.id) == nil)

        workspace.updatePanelShellActivityState(panelId: backgroundPanel.id, state: .commandRunning)
        workspace.recordAgentPID(
            key: "claude_code.top-tab-mark",
            pid: pid_t(ProcessInfo.processInfo.processIdentifier),
            panelId: backgroundPanel.id,
            refreshPorts: false
        )

        // The agent runs in the background tab's panel, so only that tab shows its mark.
        #expect(workspace.topTabAgentIconAsset(backgroundTab.id) == expectedAsset)
        #expect(workspace.topTabAgentIconAsset(visibleTab.id) == nil)
        #expect(workspace.topTabIcon(visibleTab.id) != nil)
    }

    // MARK: dragging a top tab drops it into a gap between tabs

    @Test func topTabDropGapMapsToTheIndexMoveTopTabNeeds() throws {
        let workspace = Workspace()
        let first = try #require(workspace.focusedTerminalPanel)
        _ = try #require(workspace.addTopTab(select: false, inheritingDirectoryFrom: first.id))
        _ = try #require(workspace.addTopTab(select: false, inheritingDirectoryFrom: first.id))
        let ids = workspace.topTabs.map(\.id)
        #expect(ids.count == 3)

        // Gaps run 0...3: before tab 0, 1, 2, and after tab 2.
        // The gaps on either side of a tab leave it where it is.
        #expect(workspace.topTabDestinationIndex(moving: ids[0], intoGapBefore: 0) == nil)
        #expect(workspace.topTabDestinationIndex(moving: ids[0], intoGapBefore: 1) == nil)
        #expect(workspace.topTabDestinationIndex(moving: ids[2], intoGapBefore: 2) == nil)
        #expect(workspace.topTabDestinationIndex(moving: ids[2], intoGapBefore: 3) == nil)
        // Moving right lands one earlier than the gap, since the tab leaves first.
        #expect(workspace.topTabDestinationIndex(moving: ids[0], intoGapBefore: 2) == 1)
        #expect(workspace.topTabDestinationIndex(moving: ids[0], intoGapBefore: 3) == 2)
        #expect(workspace.topTabDestinationIndex(moving: ids[1], intoGapBefore: 3) == 2)
        // Moving left lands on the gap itself.
        #expect(workspace.topTabDestinationIndex(moving: ids[2], intoGapBefore: 0) == 0)
        #expect(workspace.topTabDestinationIndex(moving: ids[1], intoGapBefore: 0) == 0)
        // An unknown tab has nowhere to go.
        #expect(workspace.topTabDestinationIndex(moving: UUID(), intoGapBefore: 0) == nil)

        let destination = try #require(workspace.topTabDestinationIndex(moving: ids[0], intoGapBefore: 3))
        workspace.moveTopTab(id: ids[0], to: destination)
        #expect(workspace.topTabs.map(\.id) == [ids[1], ids[2], ids[0]])
    }

    // MARK: control-socket readers (tree, list-surfaces, list-panes) see every top tab

    /// `tree` feeds tools that decide whether an agent is alive (a surface that
    /// is missing from it reads as a closed tab), so a surface in a background
    /// top tab has to land in a pane there, not only exist workspace-wide.
    @Test func controlSummariesPlaceBackgroundTopTabSurfacesInTheirPane() throws {
        let workspace = Workspace()
        let backgroundPanel = try #require(workspace.focusedTerminalPanel)
        let backgroundPane = try #require(workspace.topTabs[0].controller.allPaneIds.first)
        _ = try #require(workspace.addTopTab(select: true, inheritingDirectoryFrom: backgroundPanel.id))
        let visiblePanelId = try #require(workspace.focusedTerminalPanel?.id)
        let visiblePane = try #require(workspace.activeBonsplitController.allPaneIds.first)

        let controller = TerminalController.shared
        let surfaces = controller.controlSurfaceSummaries(workspace: workspace)
        #expect(surfaces.first { $0.surfaceID == backgroundPanel.id }?.paneID == backgroundPane.id)
        #expect(surfaces.first { $0.surfaceID == visiblePanelId }?.paneID == visiblePane.id)

        let panes = controller.controlPaneSummaries(
            workspace: workspace,
            snapshot: workspace.activeBonsplitController.layoutSnapshot()
        )
        #expect(Set(panes.map(\.paneID)) == Set(workspace.allTopTabPaneIds.map(\.id)))
        let backgroundSummary = try #require(panes.first { $0.paneID == backgroundPane.id })
        #expect(backgroundSummary.surfaceIDs == [backgroundPanel.id])
        #expect(backgroundSummary.selectedSurfaceID == backgroundPanel.id)
    }

    @Test func controlSummariesAreUnchangedWithOneTopTab() throws {
        let workspace = Workspace()
        let panel = try #require(workspace.focusedTerminalPanel)
        let pane = try #require(workspace.activeBonsplitController.allPaneIds.first)

        let controller = TerminalController.shared
        #expect(controller.controlSurfaceSummaries(workspace: workspace).first { $0.surfaceID == panel.id }?.paneID == pane.id)
        let panes = controller.controlPaneSummaries(
            workspace: workspace,
            snapshot: workspace.activeBonsplitController.layoutSnapshot()
        )
        #expect(panes.map(\.paneID) == [pane.id])
    }

    // MARK: existing tab actions target top tabs when enabled (Task 5)

    @Test func surfaceActionsTargetTopTabsWhenEnabled() throws {
        try withTopTabsSetting(true) {
            let manager = TabManager()
            let workspace = try #require(manager.selectedWorkspace)
            manager.newSurface()
            manager.newSurface()
            #expect(workspace.topTabs.count == 3)
            #expect(workspace.activeBonsplitController.allTabIds.count == 1)
            #expect(workspace.selectedTopTabId == workspace.topTabs[2].id)
            manager.selectNextSurface()
            #expect(workspace.selectedTopTabId == workspace.topTabs[0].id)
            manager.selectPreviousSurface()
            #expect(workspace.selectedTopTabId == workspace.topTabs[2].id)
            manager.selectSurface(at: 1)
            #expect(workspace.selectedTopTabId == workspace.topTabs[1].id)
            manager.selectLastSurface()
            #expect(workspace.selectedTopTabId == workspace.topTabs[2].id)
            let movingId = workspace.selectedTopTabId
            workspace.moveSelectedSurface(by: -1)
            #expect(workspace.topTabs[1].id == movingId)
            #expect(!workspace.canMoveSurfaceBetweenPanes)
        }
    }

    @Test func surfaceActionsUnchangedWhenDisabled() throws {
        try withTopTabsSetting(false) {
            let manager = TabManager()
            let workspace = try #require(manager.selectedWorkspace)
            manager.newSurface()
            #expect(workspace.topTabs.count == 1)
            #expect(workspace.activeBonsplitController.allTabIds.count == 2)
            #expect(workspace.canMoveSurfaceBetweenPanes)
        }
    }

    @Test func canvasModeIsUnavailableWithSeveralTopTabs() throws {
        let workspace = Workspace()
        let firstPanel = try #require(workspace.focusedTerminalPanel)
        _ = try #require(workspace.addTopTab(select: true, inheritingDirectoryFrom: firstPanel.id))
        workspace.setLayoutMode(.canvas)
        #expect(workspace.layoutMode != .canvas)
    }

    // MARK: close semantics (Task 6)

    @Test func closingLastPaneOfTopTabClosesTabAndSelectsRightNeighbour() throws {
        let workspace = Workspace()
        let p0 = try #require(workspace.focusedTerminalPanel)
        let t1 = try #require(workspace.addTopTab(select: true, inheritingDirectoryFrom: p0.id))
        let p1 = try #require(workspace.focusedTerminalPanel)
        let t2 = try #require(workspace.addTopTab(select: false, inheritingDirectoryFrom: p0.id))
        #expect(workspace.closePanel(p1.id, force: true))
        #expect(!workspace.topTabs.contains { $0.id == t1.id })
        #expect(workspace.topTabs.count == 2)
        #expect(workspace.selectedTopTabId == t2.id)
    }

    @Test func closingLastPaneOfLastTabKeepsExistingBehavior() throws {
        let workspace = Workspace()
        let p0 = try #require(workspace.focusedTerminalPanel)
        _ = workspace.closePanel(p0.id, force: true)
        #expect(workspace.topTabs.count == 1)
        #expect(workspace.panels.count == 1)
    }

    @Test func closeTopTabClosesEveryPanelInIt() throws {
        let workspace = Workspace()
        let p0 = try #require(workspace.focusedTerminalPanel)
        let t1 = try #require(workspace.addTopTab(select: true, inheritingDirectoryFrom: p0.id))
        let p1 = try #require(workspace.focusedTerminalPanel)
        let p2 = try #require(workspace.newTerminalSplit(from: p1.id, orientation: .horizontal))
        workspace.closeTopTab(id: t1.id)
        #expect(workspace.topTabs.count == 1)
        #expect(workspace.panels[p1.id] == nil)
        #expect(workspace.panels[p2.id] == nil)
        #expect(workspace.panels[p0.id] != nil)
        #expect(workspace.selectedTopTabId == workspace.topTabs[0].id)
    }

    @Test func idleTopTabNeedsNoConfirmation() throws {
        let workspace = Workspace()
        let p0 = try #require(workspace.focusedTerminalPanel)
        let t1 = try #require(workspace.addTopTab(select: true, inheritingDirectoryFrom: p0.id))
        #expect(!workspace.topTabNeedsCloseConfirmation(t1.id))
    }

    @Test func closeOtherTabsClosesOtherTopTabsWhenEnabled() throws {
        try withTopTabsSetting(true) {
            let manager = TabManager()
            let workspace = try #require(manager.selectedWorkspace)
            manager.newSurface()
            manager.newSurface()
            #expect(workspace.topTabs.count == 3)
            #expect(manager.canCloseOtherTabsInFocusedPane())
            let keep = workspace.selectedTopTabId
            manager.closeOtherTabsInFocusedPaneWithConfirmation()
            #expect(workspace.topTabs.count == 1)
            #expect(workspace.selectedTopTabId == keep)
        }
    }

    // MARK: view and portals (Task 7)

    @Test func topTabTitleFollowsCustomTitleThenFocusedPanel() throws {
        let workspace = Workspace()
        let first = workspace.topTabs[0]
        #expect(!workspace.topTabTitle(first.id).isEmpty)
        workspace.renameTopTab(id: first.id, title: "logs")
        #expect(workspace.topTabTitle(first.id) == "logs")
        workspace.renameTopTab(id: first.id, title: "  ")
        #expect(first.customTitle == nil)
    }

    @Test func moveTopTabReordersTabs() throws {
        let workspace = Workspace()
        let p0 = try #require(workspace.focusedTerminalPanel)
        let first = workspace.topTabs[0]
        let second = try #require(workspace.addTopTab(select: false, inheritingDirectoryFrom: p0.id))
        workspace.moveTopTab(id: second.id, to: 0)
        #expect(workspace.topTabs.map(\.id) == [second.id, first.id])
    }

    // MARK: toggle conversion (Task 8a enable)

    @Test func enablingSplitsMultiTabPaneWithoutClosingSurfaces() throws {
        try withTopTabsSetting(false) {
            let manager = TabManager()
            let workspace = try #require(manager.selectedWorkspace)
            for _ in 0..<3 { manager.newSurface() }
            let pane = try #require(workspace.activeBonsplitController.focusedPaneId)
            _ = workspace.newBrowserSurface(inPane: pane, url: URL(string: "about:blank"), focus: false)
            let before = Set(workspace.panels.keys)
            #expect(before.count == 5)
            let focusedBefore = workspace.focusedPanelId
            UserDefaults.standard.set(true, forKey: SettingCatalog().app.workspaceTopTabs.userDefaultsKey)
            workspace.applyTopTabsEnabled(true)
            #expect(Set(workspace.panels.keys) == before)
            #expect(workspace.topTabs.count == 5)
            #expect(workspace.topTabs.allSatisfy { $0.controller.allTabIds.count == 1 })
            #expect(workspace.focusedPanelId == focusedBefore)
            #expect(workspace.activeBonsplitController.configuration.tabBarVisibility == .multipleTabs)
        }
    }

    @Test func enablingTwiceIsANoOp() throws {
        try withTopTabsSetting(true) {
            let workspace = Workspace()
            workspace.applyTopTabsEnabled(true)
            workspace.applyTopTabsEnabled(true)
            #expect(workspace.topTabs.count == 1)
        }
    }

    // MARK: toggle conversion (Task 8b disable)

    @Test func disablingMovesOtherTabsToNewWorkspacesBelow() throws {
        try withTopTabsSetting(true) {
            let manager = TabManager()
            let workspace = try #require(manager.selectedWorkspace)
            manager.newSurface()
            manager.newSurface()
            let keptTab = workspace.topTabs[1]
            workspace.selectTopTab(id: keptTab.id)
            let panelCountBefore = manager.tabs.reduce(0) { $0 + $1.panels.count }
            let index = try #require(manager.tabs.firstIndex { $0 === workspace })
            UserDefaults.standard.set(false, forKey: SettingCatalog().app.workspaceTopTabs.userDefaultsKey)
            workspace.applyTopTabsEnabled(false)
            #expect(workspace.topTabs.count == 1)
            #expect(workspace.topTabs[0].id == keptTab.id)
            #expect(manager.tabs.count == 3)
            #expect(manager.tabs[index + 1].panels.count == 1)
            #expect(manager.tabs[index + 2].panels.count == 1)
            #expect(manager.tabs.reduce(0) { $0 + $1.panels.count } == panelCountBefore)
            #expect(manager.tabs[index + 1].title.contains(" · "))
        }
    }

    @Test func disablingKeepsAMovedTabsSplitLayout() throws {
        try withTopTabsSetting(true) {
            let manager = TabManager()
            let workspace = try #require(manager.selectedWorkspace)
            manager.newSurface()
            let splitTab = workspace.topTabs[1]
            let leftPanel = try #require(workspace.focusedTerminalPanel)
            let rightPanel = try #require(workspace.newTerminalSplit(from: leftPanel.id, orientation: .horizontal))
            workspace.selectTopTab(id: workspace.topTabs[0].id)
            UserDefaults.standard.set(false, forKey: SettingCatalog().app.workspaceTopTabs.userDefaultsKey)
            workspace.applyTopTabsEnabled(false)
            #expect(!workspace.topTabs.contains { $0.id == splitTab.id })
            let moved = try #require(manager.tabs.first { $0.panels[leftPanel.id] != nil })
            #expect(moved !== workspace)
            #expect(moved.panels[rightPanel.id] != nil)
            #expect(moved.activeBonsplitController.allPaneIds.count == 2)
        }
    }

    // MARK: persistence (Task 9)

    @Test func roundTripsThreeTopTabsWithSelectionAndTitle() throws {
        let workspace = Workspace()
        let p0 = try #require(workspace.focusedTerminalPanel)
        _ = try #require(workspace.addTopTab(select: false, inheritingDirectoryFrom: p0.id))
        let t2 = try #require(workspace.addTopTab(select: true, inheritingDirectoryFrom: p0.id))
        let p2 = try #require(workspace.focusedTerminalPanel)
        _ = workspace.newTerminalSplit(from: p2.id, orientation: .vertical)
        workspace.renameTopTab(id: t2.id, title: "logs")
        let snapshot = workspace.sessionSnapshot(includeScrollback: false)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionWorkspaceSnapshot.self, from: data)
        let restored = Workspace()
        _ = restored.restoreSessionSnapshot(decoded)
        let expectedIndex = try #require(workspace.topTabs.firstIndex { $0.id == t2.id })
        #expect(restored.topTabs.count == 3)
        #expect(restored.topTabs.firstIndex { $0.id == restored.selectedTopTabId } == expectedIndex)
        #expect(restored.topTabs[expectedIndex].customTitle == "logs")
        #expect(restored.topTabs[expectedIndex].controller.allPaneIds.count == 2)
        #expect(restored.topTabs.allSatisfy { !$0.controller.allTabIds.isEmpty })
        #expect(restored.panels.count == workspace.panels.count)
    }

    @Test func singleTabSnapshotOmitsTopTabFields() throws {
        let snapshot = Workspace().sessionSnapshot(includeScrollback: false)
        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        #expect(!json.contains("topTabs"))
        #expect(!json.contains("selectedTopTabIndex"))
    }

    @Test func restoringASnapshotWithTopTabsWhileDisabledMovesThemToWorkspaces() throws {
        let source = Workspace()
        let p0 = try #require(source.focusedTerminalPanel)
        _ = try #require(source.addTopTab(select: false, inheritingDirectoryFrom: p0.id))
        let workspaceSnapshot = source.sessionSnapshot(includeScrollback: false)
        try withTopTabsSetting(false) {
            let manager = TabManager()
            let window = SessionTabManagerSnapshot(selectedWorkspaceIndex: 0, workspaces: [workspaceSnapshot])
            _ = manager.restoreSessionSnapshot(window)
            #expect(manager.tabs.allSatisfy { $0.topTabs.count == 1 })
            #expect(manager.tabs.count == 2)
        }
    }

    // MARK: final review fixes

    @Test func enablingKeepsPaneOrderForNewTopTabs() throws {
        try withTopTabsSetting(false) {
            let manager = TabManager()
            let workspace = try #require(manager.selectedWorkspace)
            let pane = try #require(workspace.activeBonsplitController.focusedPaneId)
            for _ in 0..<3 { manager.newSurface() }
            let selectedTab = try #require(workspace.activeBonsplitController.selectedTab(inPane: pane)?.id)
            let paneOrder = workspace.activeBonsplitController.tabs(inPane: pane).map(\.id)
            let expected = ([selectedTab] + paneOrder.filter { $0 != selectedTab })
                .map { workspace.panelIdFromSurfaceId($0) }
            UserDefaults.standard.set(true, forKey: SettingCatalog().app.workspaceTopTabs.userDefaultsKey)
            workspace.applyTopTabsEnabled(true)
            // Surfaces get new tab ids when they move, so compare panel ids.
            let actual = workspace.topTabs.map { tab in
                tab.controller.allTabIds.first.flatMap { workspace.panelIdFromSurfaceId($0) }
            }
            #expect(actual == expected)
        }
    }

    @Test func splittingAPanelInABackgroundTabSplitsThatTab() throws {
        let workspace = Workspace()
        let backgroundPanel = try #require(workspace.focusedTerminalPanel)
        let first = workspace.topTabs[0]
        let second = try #require(workspace.addTopTab(select: true, inheritingDirectoryFrom: backgroundPanel.id))
        let visiblePanelId = try #require(workspace.focusedPanelId)
        let split = workspace.newTerminalSplit(from: backgroundPanel.id, orientation: .horizontal, focus: false)
        #expect(split != nil)
        #expect(first.controller.allPaneIds.count == 2)
        #expect(second.controller.allPaneIds.count == 1)
        #expect(workspace.selectedTopTabId == second.id)
        #expect(workspace.focusedPanelId == visiblePanelId)
    }

    @Test func openingABrowserCreatesATopTabWhenEnabled() throws {
        try withTopTabsSetting(true) {
            let manager = TabManager()
            let workspace = try #require(manager.selectedWorkspace)
            let browserId = manager.openBrowser(inWorkspace: workspace.id, url: URL(string: "about:blank"))
            if browserId != nil {
                #expect(workspace.topTabs.count == 2)
                #expect(workspace.topTabs.allSatisfy { $0.controller.allTabIds.count == 1 })
                #expect(workspace.topTab(containingPanelId: try #require(browserId))?.id == workspace.selectedTopTabId)
            }
        }
    }

    private func withTopTabsSetting(_ on: Bool, _ body: () throws -> Void) rethrows {
        let key = SettingCatalog().app.workspaceTopTabs.userDefaultsKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(on, forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        try body()
    }
}
