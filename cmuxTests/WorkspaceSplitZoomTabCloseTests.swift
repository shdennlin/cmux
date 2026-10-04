import Bonsplit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("Split zoom across tab closes", .serialized)
struct WorkspaceSplitZoomTabCloseTests {
    /// Closing the selected tab of a zoomed pane must not end the zoom while the
    /// pane still holds other tabs: the pane outlives the close, so the window
    /// should keep showing it full size instead of snapping back to the split.
    /// https://github.com/manaflow-ai/cmux/issues/8363
    @Test func closingSelectedTabKeepsZoomWhilePaneStillHasTabs() throws {
        let workspace = Workspace()
        let firstPanelId = try #require(workspace.focusedPanelId)
        // Zoom needs a sibling pane; a single-pane layout cannot be zoomed.
        _ = try #require(
            workspace.newTerminalSplit(
                from: firstPanelId,
                orientation: .horizontal,
                focus: false
            )
        )
        let zoomedPaneId = try #require(workspace.paneId(forPanelId: firstPanelId))
        let secondPanel = try #require(
            workspace.newTerminalSurface(inPane: zoomedPaneId, focus: true)
        )
        let secondTabId = try #require(workspace.surfaceIdFromPanelId(secondPanel.id))
        workspace.activeBonsplitController.selectTab(secondTabId)

        #expect(workspace.toggleSplitZoom(panelId: secondPanel.id))
        #expect(workspace.activeBonsplitController.zoomedPaneId == zoomedPaneId)
        #expect(workspace.activeBonsplitController.tabs(inPane: zoomedPaneId).count == 2)
        #expect(workspace.activeBonsplitController.selectedTab(inPane: zoomedPaneId)?.id == secondTabId)

        #expect(workspace.closePanel(secondPanel.id, force: true))

        #expect(workspace.activeBonsplitController.tabs(inPane: zoomedPaneId).count == 1)
        #expect(workspace.activeBonsplitController.zoomedPaneId == zoomedPaneId)
    }

    /// The zoom still ends when the close takes the zoomed pane with it, so the
    /// surviving pane is not left hidden behind a zoom that points at nothing.
    @Test func closingLastTabInZoomedPaneEndsZoom() throws {
        let workspace = Workspace()
        let firstPanelId = try #require(workspace.focusedPanelId)
        let siblingPanel = try #require(
            workspace.newTerminalSplit(
                from: firstPanelId,
                orientation: .horizontal,
                focus: false
            )
        )
        let zoomedPaneId = try #require(workspace.paneId(forPanelId: firstPanelId))

        #expect(workspace.toggleSplitZoom(panelId: firstPanelId))
        #expect(workspace.activeBonsplitController.zoomedPaneId == zoomedPaneId)
        #expect(workspace.activeBonsplitController.tabs(inPane: zoomedPaneId).count == 1)

        #expect(workspace.closePanel(firstPanelId, force: true))

        #expect(workspace.activeBonsplitController.zoomedPaneId == nil)
        #expect(workspace.panels[siblingPanel.id] != nil)
    }
}
