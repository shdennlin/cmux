import Foundation

/// `cmux set-tab-state`, `clear-tab-state` and `list-tab-state`: the CLI face
/// of the `surface.tab_state.*` socket verbs. A display-only state for the
/// activity bar under a surface's top tab, which the bar prefers over cmux's
/// own agent state until it is cleared.
extension CMUXCLI {
    /// Resolves `--workspace` / `--surface` / `--window`. With neither a
    /// surface nor a workspace given, the target is the caller's own surface
    /// (CMUX_SURFACE_ID), so a hook or script running in a tab marks that tab.
    private func tabStateTarget(
        _ commandArgs: [String],
        client: SocketClient,
        windowOverride: String?,
        includeSurface: Bool
    ) throws -> (params: [String: Any], rest: [String]) {
        let (workspaceArg, rem0) = parseOption(commandArgs, name: "--workspace")
        let (surfaceArg, rem1) = parseOption(rem0, name: "--surface")
        let (windowArg, rem2) = parseOption(rem1, name: "--window")
        var params: [String: Any] = [:]
        let windowHandle = try normalizeWindowHandle(windowArg ?? windowOverride, client: client)
        if let windowHandle { params["window_id"] = windowHandle }
        let workspaceHandle = try normalizeWorkspaceHandle(
            workspaceArg,
            client: client,
            windowHandle: windowHandle,
            allowCurrent: true
        )
        if let workspaceHandle { params["workspace_id"] = workspaceHandle }
        if includeSurface {
            let ambientSurface = workspaceArg == nil
                ? ProcessInfo.processInfo.environment["CMUX_SURFACE_ID"]
                : nil
            if let surfaceHandle = try normalizeSurfaceHandle(
                surfaceArg ?? ambientSurface,
                client: client,
                workspaceHandle: workspaceHandle,
                windowHandle: windowHandle
            ) {
                params["surface_id"] = surfaceHandle
            }
        }
        return (params, rem2.filter { $0 != "--json" })
    }

    /// `cmux set-tab-state <running|needs-input|error|idle>`.
    func runSetTabState(
        commandArgs: [String],
        client: SocketClient,
        jsonOutput: Bool,
        idFormat: CLIIDFormat,
        windowOverride: String?
    ) throws {
        let (params, rest) = try tabStateTarget(
            commandArgs, client: client, windowOverride: windowOverride, includeSurface: true
        )
        guard rest.count == 1, let state = rest.first else {
            throw CLIError(message: "Usage: cmux set-tab-state <running|needs-input|error|idle> [--surface <id|ref|index>] [--workspace <id|ref|index>] [--window <id|ref|index>]")
        }
        var setParams = params
        setParams["state"] = state
        let payload = try client.sendV2(method: "surface.tab_state.set", params: setParams)
        printV2Payload(
            payload,
            jsonOutput: jsonOutput,
            idFormat: idFormat,
            fallbackText: tabStateLine(payload, idFormat: idFormat)
        )
    }

    /// `cmux clear-tab-state`: hand the tab back to cmux's own agent state.
    func runClearTabState(
        commandArgs: [String],
        client: SocketClient,
        jsonOutput: Bool,
        idFormat: CLIIDFormat,
        windowOverride: String?
    ) throws {
        let (params, rest) = try tabStateTarget(
            commandArgs, client: client, windowOverride: windowOverride, includeSurface: true
        )
        guard rest.isEmpty else {
            throw CLIError(message: "Usage: cmux clear-tab-state [--surface <id|ref|index>] [--workspace <id|ref|index>] [--window <id|ref|index>]")
        }
        let payload = try client.sendV2(method: "surface.tab_state.clear", params: params)
        printV2Payload(
            payload,
            jsonOutput: jsonOutput,
            idFormat: idFormat,
            fallbackText: tabStateLine(payload, idFormat: idFormat)
        )
    }

    /// `cmux list-tab-state`: every surface in the workspace with a state set.
    func runListTabState(
        commandArgs: [String],
        client: SocketClient,
        jsonOutput: Bool,
        idFormat: CLIIDFormat,
        windowOverride: String?
    ) throws {
        let (params, rest) = try tabStateTarget(
            commandArgs, client: client, windowOverride: windowOverride, includeSurface: false
        )
        guard rest.isEmpty else {
            throw CLIError(message: "Usage: cmux list-tab-state [--workspace <id|ref|index>] [--window <id|ref|index>] [--json]")
        }
        let payload = try client.sendV2(method: "surface.tab_state.list", params: params)
        let entries = payload["entries"] as? [[String: Any]] ?? []
        let lines = entries.map { tabStateLine($0, idFormat: idFormat) }
        printV2Payload(
            payload,
            jsonOutput: jsonOutput,
            idFormat: idFormat,
            fallbackText: lines.isEmpty ? "No tab states" : lines.joined(separator: "\n")
        )
    }

    /// `<surface> <state>`, with `none` for a cleared state.
    private func tabStateLine(_ payload: [String: Any], idFormat: CLIIDFormat) -> String {
        let surface = formatHandle(payload, kind: "surface", idFormat: idFormat) ?? "?"
        let state = (payload["state"] as? String)?.replacingOccurrences(of: "_", with: "-") ?? "none"
        return "\(surface) \(state)"
    }
}
