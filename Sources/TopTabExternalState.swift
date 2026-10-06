/// What an external tool (`cmux set-tab-state`) says a panel's work is doing.
///
/// Display-only: it changes the activity bar under the panel's top tab and
/// nothing else, so a tool cannot steer agent hibernation or the sidebar.
enum TopTabExternalState: Equatable {
    case running
    case needsInput
    case error
    /// Explicitly not working: hides the bar even when cmux's own agent state
    /// still says running, which is how a tool corrects a stuck lifecycle.
    case idle

    /// The bar this state draws, or `nil` for ``idle``.
    var activityState: TopTabActivityState? {
        switch self {
        case .running: return .running
        case .needsInput: return .needsInput
        case .error: return .error
        case .idle: return nil
        }
    }
}
