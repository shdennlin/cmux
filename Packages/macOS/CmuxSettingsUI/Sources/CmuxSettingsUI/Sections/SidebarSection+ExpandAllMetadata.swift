import CmuxSettings
import SwiftUI

extension SidebarSection {
    /// The `sidebar.expandAllCustomMetadata` toggle row. It controls how the
    /// custom metadata rows collapse, so it is disabled while "Hide All
    /// Details" is on or custom metadata is off.
    @ViewBuilder
    var expandAllMetadataRow: some View {
        SettingsCardRow(
            configurationReview: .json("sidebar.expandAllCustomMetadata"),
            String(localized: "settings.app.expandAllMetadata", defaultValue: "Always Show All Custom Metadata"),
            subtitle: String(localized: "settings.app.expandAllMetadata.subtitle", defaultValue: "Show every custom metadata row instead of the first few behind a Show more link. Useful when a tool reports one row per agent and every row matters.")
        ) {
            Toggle("", isOn: Binding(get: { expandAllMetadata.current }, set: { expandAllMetadata.set($0) }))
                .labelsHidden()
                .controlSize(.small)
        }
        .disabled(hideAll.current || !showMetadata.current)
        SettingsCardDivider()
    }
}
