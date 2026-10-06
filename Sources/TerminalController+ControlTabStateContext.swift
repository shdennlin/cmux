import CmuxControlSocket
import Foundation

/// The tab-state witnesses for ``ControlCommandCoordinator``: resolves the
/// target surface and stores a display-only state on it for the activity bar
/// under its top tab.
///
/// Runs on the main actor through the coordinator's main hop
/// (`v2MainActorResponse`): it writes the workspace's observable store and has
/// to answer `not_found` synchronously. Tools push a state only when it
/// changes, so this is not a telemetry hot path. It changes no focus or
/// selection.
extension TerminalController: ControlTabStateContext {
    private enum TabStateWorkspaceResolution {
        case tabManagerUnavailable
        case notFound
        case found(Workspace)
    }

    private enum TabStateTarget {
        case tabManagerUnavailable
        case notFound
        case found(workspace: Workspace, panelId: UUID)
    }

    /// The explicit workspace owner-first, else the routed window's selected
    /// workspace, as the other workspace-scoped commands resolve it.
    private func resolveTabStateWorkspace(
        routing: ControlRoutingSelectors,
        workspaceID: UUID?
    ) -> TabStateWorkspaceResolution {
        if let workspaceID {
            if let owner = AppDelegate.shared?.tabManagerFor(tabId: workspaceID),
               let workspace = owner.tabs.first(where: { $0.id == workspaceID }) {
                return .found(workspace)
            }
            guard let tabManager = resolveTabManager(routing: routing) else { return .tabManagerUnavailable }
            guard let workspace = tabManager.tabs.first(where: { $0.id == workspaceID }) else { return .notFound }
            return .found(workspace)
        }
        guard let tabManager = resolveTabManager(routing: routing) else { return .tabManagerUnavailable }
        guard let selectedId = tabManager.selectedTabId,
              let workspace = tabManager.tabs.first(where: { $0.id == selectedId }) else { return .notFound }
        return .found(workspace)
    }

    /// The explicit surface wherever it lives (and it must be in the explicit
    /// workspace, when one is given), else the resolved workspace's focused one.
    private func resolveTabStateTarget(
        routing: ControlRoutingSelectors,
        workspaceID: UUID?,
        surfaceID: UUID?
    ) -> TabStateTarget {
        if let surfaceID {
            guard let located = AppDelegate.shared?.workspaceContainingPanel(
                panelId: surfaceID,
                preferredWorkspaceId: workspaceID
            ) else { return .notFound }
            if let workspaceID, located.workspace.id != workspaceID { return .notFound }
            return .found(workspace: located.workspace, panelId: surfaceID)
        }
        switch resolveTabStateWorkspace(routing: routing, workspaceID: workspaceID) {
        case .tabManagerUnavailable:
            return .tabManagerUnavailable
        case .notFound:
            return .notFound
        case .found(let workspace):
            guard let panelId = workspace.focusedPanelId else { return .notFound }
            return .found(workspace: workspace, panelId: panelId)
        }
    }

    func controlSetTabState(
        routing: ControlRoutingSelectors,
        workspaceID: UUID?,
        surfaceID: UUID?,
        state: ControlTabState
    ) -> ControlTabStateResolution {
        switch resolveTabStateTarget(routing: routing, workspaceID: workspaceID, surfaceID: surfaceID) {
        case .tabManagerUnavailable:
            return .tabManagerUnavailable
        case .notFound:
            return .notFound
        case .found(let workspace, let panelId):
            guard workspace.setExternalTabState(TopTabExternalState(state), panelId: panelId) else { return .notFound }
            return .applied(workspaceID: workspace.id, surfaceID: panelId, state: state)
        }
    }

    func controlClearTabState(
        routing: ControlRoutingSelectors,
        workspaceID: UUID?,
        surfaceID: UUID?
    ) -> ControlTabStateResolution {
        switch resolveTabStateTarget(routing: routing, workspaceID: workspaceID, surfaceID: surfaceID) {
        case .tabManagerUnavailable:
            return .tabManagerUnavailable
        case .notFound:
            return .notFound
        case .found(let workspace, let panelId):
            guard workspace.clearExternalTabState(panelId: panelId) else { return .notFound }
            return .applied(workspaceID: workspace.id, surfaceID: panelId, state: nil)
        }
    }

    func controlListTabStates(
        routing: ControlRoutingSelectors,
        workspaceID: UUID?
    ) -> ControlTabStateListResolution {
        switch resolveTabStateWorkspace(routing: routing, workspaceID: workspaceID) {
        case .tabManagerUnavailable:
            return .tabManagerUnavailable
        case .notFound:
            return .notFound
        case .found(let workspace):
            let entries = workspace.externalTabStateEntries()
                .map { ControlTabStateEntry(surfaceID: $0.panelId, state: ControlTabState($0.state)) }
                .sorted { $0.surfaceID.uuidString < $1.surfaceID.uuidString }
            return .listed(workspaceID: workspace.id, entries: entries)
        }
    }
}

private extension TopTabExternalState {
    init(_ state: ControlTabState) {
        switch state {
        case .running: self = .running
        case .needsInput: self = .needsInput
        case .error: self = .error
        case .idle: self = .idle
        }
    }
}

private extension ControlTabState {
    init(_ state: TopTabExternalState) {
        switch state {
        case .running: self = .running
        case .needsInput: self = .needsInput
        case .error: self = .error
        case .idle: self = .idle
        }
    }
}
