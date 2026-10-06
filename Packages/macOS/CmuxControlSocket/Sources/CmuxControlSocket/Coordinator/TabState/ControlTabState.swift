/// What an external tool says a surface's work is doing, shown as the activity
/// bar under its top tab (`surface.tab_state.set`).
///
/// It is display-only: it changes what the bar draws and nothing else, so a
/// tool cannot use it to steer agent hibernation or the sidebar.
public enum ControlTabState: String, Sendable, Equatable, CaseIterable {
    /// Work is in progress; the bar sweeps.
    case running
    /// The work is parked until the person answers; the bar is solid amber.
    case needsInput = "needs_input"
    /// The work reported a failure; the bar is solid red.
    case error
    /// Explicitly not working: the bar shows nothing, even when cmux's own
    /// agent state still says running.
    case idle

    /// Parses a wire or CLI spelling, ignoring case and surrounding space.
    /// `needs-input` and `needs_input` name the same state.
    ///
    /// - Parameter raw: The value as it arrived.
    public init?(wireValue raw: String) {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        self.init(rawValue: normalized)
    }
}
