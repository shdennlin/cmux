import Bonsplit
import Foundation

/// Owns the active container projection for one file-preview tab.
@MainActor
protocol FilePreviewTabMetadataHost: AnyObject {
    /// The split controller that holds `panelId`'s tab and receives its metadata updates.
    func filePreviewTabController(forPanelId panelId: UUID) -> BonsplitController?

    /// Returns the host-owned tab for `panelId`.
    func filePreviewTabId(forPanelId panelId: UUID) -> TabID?

    /// Resolves container-specific title and custom-title policy.
    func filePreviewTabTitlePresentation(
        for metadata: FilePreviewTabMetadata,
        panelId: UUID,
        existingTab: Bonsplit.Tab
    ) -> (title: String?, hasCustomTitle: Bool?)
}

extension FilePreviewTabMetadataHost {
    /// Applies one panel-owned metadata snapshot to the current host tab.
    func applyFilePreviewTabMetadata(
        _ metadata: FilePreviewTabMetadata,
        panelId: UUID
    ) {
        guard let controller = filePreviewTabController(forPanelId: panelId),
              let tabId = filePreviewTabId(forPanelId: panelId),
              let existing = controller.tab(tabId) else {
            return
        }

        let presentation = filePreviewTabTitlePresentation(
            for: metadata,
            panelId: panelId,
            existingTab: existing
        )
        let resolvedIcon = RenderableSystemSymbol.resolvedSurfaceTabIcon(
            metadata.displayIcon
        )
        let titleUpdate = presentation.title.flatMap {
            existing.title == $0 ? nil : $0
        }
        let customTitleUpdate = presentation.hasCustomTitle.flatMap {
            existing.hasCustomTitle == $0 ? nil : $0
        }
        let iconUpdate: String?? = existing.icon == resolvedIcon
            ? nil
            : .some(resolvedIcon)
        let dirtyUpdate: Bool? = existing.isDirty == metadata.isDirty
            ? nil
            : metadata.isDirty
        guard titleUpdate != nil
                || customTitleUpdate != nil
                || iconUpdate != nil
                || dirtyUpdate != nil else {
            return
        }
        controller.updateTab(
            tabId,
            title: titleUpdate,
            icon: iconUpdate,
            hasCustomTitle: customTitleUpdate,
            isDirty: dirtyUpdate
        )
    }
}
