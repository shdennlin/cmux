public import Foundation

/// The app-side resolution of `surface.tab_state.set` and `surface.tab_state.clear`.
public enum ControlTabStateResolution: Sendable, Equatable {
    /// No TabManager resolved from the routing selectors.
    case tabManagerUnavailable
    /// The workspace or the surface was not found.
    case notFound
    /// The state now on the surface: the one just set, or `nil` after a clear.
    case applied(workspaceID: UUID, surfaceID: UUID, state: ControlTabState?)
}
