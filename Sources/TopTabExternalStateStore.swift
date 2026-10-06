import Foundation
import Observation

/// Externally set tab states, one per panel, for the activity bars under top
/// tabs (`cmux set-tab-state`).
///
/// Observable, unlike the agent runtime, so a strip reading it in its body
/// redraws when a tool changes a state. In memory only: a state lives as long
/// as its panel, and the workspace drops it when the panel goes away.
@MainActor
@Observable
final class TopTabExternalStateStore {
    /// One panel's state, as `cmux list-tab-state` reports it.
    struct Entry: Equatable {
        let panelId: UUID
        let state: TopTabExternalState
    }

    private(set) var statesByPanelId: [UUID: TopTabExternalState] = [:]

    func state(for panelId: UUID) -> TopTabExternalState? {
        statesByPanelId[panelId]
    }

    /// Sets a panel's state; the last writer wins.
    func set(_ state: TopTabExternalState, for panelId: UUID) {
        guard statesByPanelId[panelId] != state else { return }
        statesByPanelId[panelId] = state
    }

    /// Removes a panel's state.
    func remove(_ panelId: UUID) {
        guard statesByPanelId[panelId] != nil else { return }
        statesByPanelId.removeValue(forKey: panelId)
    }

    var entries: [Entry] {
        statesByPanelId.map { Entry(panelId: $0.key, state: $0.value) }
    }
}
