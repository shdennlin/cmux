internal import Foundation

/// The tab-state domain (`surface.tab_state.*`): a display-only state an
/// external tool sets on a surface for the activity bar under its top tab.
/// The state is validated here, so an unknown value never reaches the app.
extension ControlCommandCoordinator {
    /// Dispatches the tab-state methods this coordinator owns; returns `nil`
    /// for anything else so the core `handle(_:)` can fall through.
    ///
    /// - Parameter request: The decoded request envelope.
    /// - Returns: The command result, or `nil` if not a tab-state method.
    func handleTabState(_ request: ControlRequest) -> ControlCallResult? {
        switch request.method {
        case "surface.tab_state.set":
            return tabStateSet(request.params)
        case "surface.tab_state.clear":
            return tabStateClear(request.params)
        case "surface.tab_state.list":
            return tabStateList(request.params)
        default:
            return nil
        }
    }

    /// `surface.tab_state.set` — show `state` on the surface's tab.
    func tabStateSet(_ params: [String: JSONValue]) -> ControlCallResult {
        guard let raw = string(params, "state") else {
            return .err(code: "invalid_params", message: "Missing or invalid state", data: nil)
        }
        guard let state = ControlTabState(wireValue: raw) else {
            return .err(
                code: "invalid_params",
                message: "state must be one of: running, needs-input, error, idle",
                data: .object(["state": .string(raw)])
            )
        }
        return tabStateResult(
            context?.controlSetTabState(
                routing: routingSelectors(params),
                workspaceID: uuid(params, "workspace_id"),
                surfaceID: uuid(params, "surface_id"),
                state: state
            ) ?? .tabManagerUnavailable
        )
    }

    /// `surface.tab_state.clear` — hand the tab back to cmux's own agent state.
    func tabStateClear(_ params: [String: JSONValue]) -> ControlCallResult {
        tabStateResult(
            context?.controlClearTabState(
                routing: routingSelectors(params),
                workspaceID: uuid(params, "workspace_id"),
                surfaceID: uuid(params, "surface_id")
            ) ?? .tabManagerUnavailable
        )
    }

    /// `surface.tab_state.list` — every surface in the workspace with a state set.
    func tabStateList(_ params: [String: JSONValue]) -> ControlCallResult {
        let resolution = context?.controlListTabStates(
            routing: routingSelectors(params),
            workspaceID: uuid(params, "workspace_id")
        ) ?? .tabManagerUnavailable
        switch resolution {
        case .tabManagerUnavailable:
            return .err(code: "unavailable", message: "TabManager not available", data: nil)
        case .notFound:
            return .err(code: "not_found", message: "Workspace not found", data: nil)
        case .listed(let workspaceID, let entries):
            return .ok(.object([
                "workspace_id": .string(workspaceID.uuidString),
                "workspace_ref": ref(.workspace, workspaceID),
                "entries": .array(entries.map { entry in
                    .object([
                        "surface_id": .string(entry.surfaceID.uuidString),
                        "surface_ref": ref(.surface, entry.surfaceID),
                        "state": .string(entry.state.rawValue),
                    ])
                }),
            ]))
        }
    }

    private func tabStateResult(_ resolution: ControlTabStateResolution) -> ControlCallResult {
        switch resolution {
        case .tabManagerUnavailable:
            return .err(code: "unavailable", message: "TabManager not available", data: nil)
        case .notFound:
            return .err(code: "not_found", message: "Workspace or surface not found", data: nil)
        case .applied(let workspaceID, let surfaceID, let state):
            return .ok(.object([
                "workspace_id": .string(workspaceID.uuidString),
                "workspace_ref": ref(.workspace, workspaceID),
                "surface_id": .string(surfaceID.uuidString),
                "surface_ref": ref(.surface, surfaceID),
                "state": state.map { .string($0.rawValue) } ?? .null,
            ]))
        }
    }
}
