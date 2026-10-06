public import Foundation

/// One surface's externally set tab state, as `surface.tab_state.list` reports it.
public struct ControlTabStateEntry: Sendable, Equatable {
    /// The surface the state was set on.
    public let surfaceID: UUID
    /// The state the last writer set.
    public let state: ControlTabState

    /// Creates an entry.
    ///
    /// - Parameters:
    ///   - surfaceID: The surface the state was set on.
    ///   - state: The state the last writer set.
    public init(surfaceID: UUID, state: ControlTabState) {
        self.surfaceID = surfaceID
        self.state = state
    }
}
