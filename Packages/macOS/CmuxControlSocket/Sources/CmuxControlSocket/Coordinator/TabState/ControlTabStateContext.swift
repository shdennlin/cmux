public import Foundation

/// The tab-state slice of the control-command seam (a constituent of the
/// ``ControlCommandContext`` umbrella): a display-only state an external tool
/// sets on a surface, which the activity bar under its top tab prefers over
/// cmux's own agent state.
///
/// The app target conforms by resolving the surface — the explicit
/// `surfaceID` workspace-owner-first, else the resolved workspace's focused
/// surface — and storing the state per surface. A state lives as long as its
/// surface and is not persisted. No app types cross the seam.
@MainActor
public protocol ControlTabStateContext: AnyObject {
    /// Sets a surface's tab state for `surface.tab_state.set`; the last writer wins.
    ///
    /// - Parameters:
    ///   - routing: The routing selectors used for TabManager resolution.
    ///   - workspaceID: The explicit target workspace, or `nil` to find it
    ///     from the surface or the routed window.
    ///   - surfaceID: The target surface, or `nil` for the workspace's
    ///     focused surface.
    ///   - state: The state to show.
    /// - Returns: The resolution.
    func controlSetTabState(
        routing: ControlRoutingSelectors,
        workspaceID: UUID?,
        surfaceID: UUID?,
        state: ControlTabState
    ) -> ControlTabStateResolution

    /// Clears a surface's tab state for `surface.tab_state.clear`, handing the
    /// bar back to cmux's own agent state.
    ///
    /// - Parameters:
    ///   - routing: The routing selectors used for TabManager resolution.
    ///   - workspaceID: The explicit target workspace, or `nil` to find it
    ///     from the surface or the routed window.
    ///   - surfaceID: The target surface, or `nil` for the workspace's
    ///     focused surface.
    /// - Returns: The resolution, with a `nil` state.
    func controlClearTabState(
        routing: ControlRoutingSelectors,
        workspaceID: UUID?,
        surfaceID: UUID?
    ) -> ControlTabStateResolution

    /// Lists the externally set tab states in one workspace for `surface.tab_state.list`.
    ///
    /// - Parameters:
    ///   - routing: The routing selectors used for TabManager resolution.
    ///   - workspaceID: The explicit target workspace, or `nil` for the
    ///     resolved window's selected workspace.
    /// - Returns: The resolution.
    func controlListTabStates(
        routing: ControlRoutingSelectors,
        workspaceID: UUID?
    ) -> ControlTabStateListResolution
}
