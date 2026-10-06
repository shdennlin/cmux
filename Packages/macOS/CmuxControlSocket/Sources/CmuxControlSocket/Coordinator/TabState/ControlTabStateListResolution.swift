public import Foundation

/// The app-side resolution of `surface.tab_state.list`.
public enum ControlTabStateListResolution: Sendable, Equatable {
    /// No TabManager resolved from the routing selectors.
    case tabManagerUnavailable
    /// The workspace was not found (or no workspace is selected).
    case notFound
    /// Every surface in the workspace that has an externally set state.
    case listed(workspaceID: UUID, entries: [ControlTabStateEntry])
}
