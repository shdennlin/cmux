import Bonsplit
import Foundation

/// One tab above a workspace's split area. It owns the whole split layout
/// shown while it is selected; panels stay owned by the workspace.
@MainActor
final class WorkspaceTopTab: Identifiable {
    let id: UUID
    let controller: BonsplitController
    var customTitle: String?

    init(id: UUID = UUID(), controller: BonsplitController, customTitle: String? = nil) {
        self.id = id
        self.controller = controller
        self.customTitle = customTitle
    }
}
