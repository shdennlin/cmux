/// What the work behind a top tab is doing, drawn as a bar under its title.
///
/// Only states that are happening now, that ask for the person, or that
/// finished without being looked at get a bar; everything settled (idle,
/// waiting on a wakeup, a pull request) draws none.
enum TopTabActivityState: Equatable {
    /// The work finished and the person has not looked at it yet.
    case done
    /// Work is in progress.
    case running
    /// The work is parked until the person answers.
    case needsInput
    /// The work reported a failure.
    case error

    /// How loud the state is. A tab with several panels shows its loudest, so a
    /// tab hiding a pane that needs the person still asks for them.
    var urgency: Int {
        switch self {
        case .done: return 0
        case .running: return 1
        case .needsInput: return 2
        case .error: return 3
        }
    }

    /// The bar's colour as sRGB hex for the light or the dark appearance.
    ///
    /// The sidebar rows are painted from the same values by the agent-status
    /// daemon, so one state is one colour on both. Change them together.
    func hex(isDark: Bool) -> String {
        switch self {
        case .done: return isDark ? "#3FCF6E" : "#34C759"
        case .running: return isDark ? "#4C8DFF" : "#2F7BF5"
        case .needsInput: return isDark ? "#F5A524" : "#E8920A"
        case .error: return isDark ? "#FF453A" : "#E5342B"
        }
    }

    /// The bar for a sidebar glyph, or nil when the glyph asks for none.
    /// Subagents read as running: the agent is working through helpers.
    init?(glyphKind: SidebarCompactStatusGlyph.Kind) {
        switch glyphKind {
        case .error: self = .error
        case .needsInput: self = .needsInput
        case .running, .subagents: self = .running
        case .waiting, .pending, .unseen, .pullRequest, .idle, .branch, .terminal: return nil
        }
    }
}
