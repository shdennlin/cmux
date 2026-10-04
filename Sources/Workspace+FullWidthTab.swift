import Bonsplit
import Foundation

extension Workspace {
    @discardableResult
    func toggleFullWidthTabMode(panelId: UUID) -> Bool {
        guard let paneId = paneId(forPanelId: panelId) else { return false }
        let nextMode = !activeBonsplitController.isFullWidthTabMode(inPane: paneId)
        guard activeBonsplitController.setFullWidthTabMode(nextMode, inPane: paneId) else { return false }
        focusPanel(panelId)
        return true
    }
}
