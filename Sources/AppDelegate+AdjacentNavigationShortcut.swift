import AppKit

extension AppDelegate {
    /// Routes adjacent surface navigation and surface/workspace reordering through
    /// the main-window context selected for the key event.
    func handleAdjacentNavigationShortcut(event: NSEvent) -> Bool {
        let routedTabs = preferredMainWindowContextForShortcutRouting(event: event)?.tabManager
            ?? tabManager
        if matchConfiguredShortcut(event: event, action: .nextSurface) {
            // Armed before the switch so the arriving surface's first portal
            // reveal can consume it; see SurfaceSwitchSlideAnimation.
            SurfaceSwitchSlideAnimation.arm(.fromTrailing)
            stepTabOrWorkspace(forward: true, tabManager: routedTabs, event: event)
            return true
        }
        if matchConfiguredShortcut(event: event, action: .prevSurface) {
            SurfaceSwitchSlideAnimation.arm(.fromLeading)
            stepTabOrWorkspace(forward: false, tabManager: routedTabs, event: event)
            return true
        }
        if matchConfiguredShortcut(event: event, action: .moveSurfaceLeft) {
            if performFocusedDockShortcut(
                .moveSurface(offset: -1),
                action: .moveSurfaceLeft,
                event: event
            ) {
                return true
            }
            routedTabs?.selectedWorkspace?.moveSelectedSurface(by: -1)
            return true
        }
        if matchConfiguredShortcut(event: event, action: .moveSurfaceRight) {
            if performFocusedDockShortcut(
                .moveSurface(offset: 1),
                action: .moveSurfaceRight,
                event: event
            ) {
                return true
            }
            routedTabs?.selectedWorkspace?.moveSelectedSurface(by: 1)
            return true
        }
        for movement in SurfacePaneMovement.allCases
        where matchesSurfacePaneMovementShortcut(event: event, movement: movement) {
            // Repeats may traverse existing panes but must not recursively create splits.
            if !performSurfacePaneMovement(
                movement,
                tabManager: routedTabs,
                preferredWindow: event.window,
                allowMissingDestinationSplit: !event.isARepeat
            ) {
                NSSound.beep()
            }
            return true
        }
        if matchConfiguredShortcut(event: event, action: .moveWorkspaceUp) {
            if moveFocusedCloudMachine(by: -1, event: event) { return true }
            routedTabs?.moveSelectedWorkspace(by: -1)
            return true
        }
        if matchConfiguredShortcut(event: event, action: .moveWorkspaceDown) {
            if moveFocusedCloudMachine(by: 1, event: event) { return true }
            routedTabs?.moveSelectedWorkspace(by: 1)
            return true
        }
        return false
    }

    /// Previous/Next from a key (``TabManager/stepTabOrWorkspace(forward:dock:)``), with the Dock
    /// that owns keyboard focus, if any.
    func stepTabOrWorkspace(forward: Bool, tabManager: TabManager?, event: NSEvent) {
        // Each action is named at its own gate call (tests/test_dock_shortcut_routing_guard.py).
        let dock = forward
            ? focusedDockStoreForShortcut(action: .nextSurface, preferredWindow: event.window)
            : focusedDockStoreForShortcut(action: .prevSurface, preferredWindow: event.window)
        tabManager?.stepTabOrWorkspace(forward: forward, dock: dock)
    }

    /// Reuses the configured workspace reorder keys when a Cloud machine
    /// header owns keyboard focus. Text fields keep their existing key routing.
    func moveFocusedCloudMachine(by offset: Int, event: NSEvent) -> Bool {
        guard let outline = (event.window ?? NSApp.keyWindow)?.firstResponder as? CloudTreeNSOutlineView else { return false }
        return outline.onMoveMachine?(offset) == true
    }

    /// Applies the shared Dock-focus gate used by shortcuts, the command
    /// palette, and the View menu.
    @discardableResult
    func performSurfacePaneMovement(
        _ movement: SurfacePaneMovement,
        tabManager: TabManager?,
        preferredWindow: NSWindow?,
        allowMissingDestinationSplit: Bool = true
    ) -> Bool {
        if let dock = focusedDockStoreForShortcut(
            action: movement.shortcutAction,
            preferredWindow: preferredWindow
        ) {
            return dock.performShortcutCommand(
                .moveSurfaceToPane(
                    movement,
                    allowMissingDestinationSplit:
                        allowMissingDestinationSplit
                )
            )
        }
        return tabManager?.selectedWorkspace?.moveFocusedSurface(
            to: movement,
            allowMissingDestinationSplit: allowMissingDestinationSplit
        ) == true
    }

    private func matchesSurfacePaneMovementShortcut(
        event: NSEvent,
        movement: SurfacePaneMovement
    ) -> Bool {
        let configuredShortcut = KeyboardShortcutSettings.shortcut(
            for: movement.shortcutAction
        )
        let configuredKey =
            configuredShortcut.secondStroke?.key ??
            configuredShortcut.firstStroke.key
        let arrowRoute: (glyph: String, keyCode: UInt16) = switch configuredKey {
        case "→": ("→", 124)
        case "↑": ("↑", 126)
        case "↓": ("↓", 125)
        default: ("←", 123)
        }
        return matchConfiguredDirectionalShortcut(
            event: event,
            action: movement.shortcutAction,
            arrowGlyph: arrowRoute.glyph,
            arrowKeyCode: arrowRoute.keyCode
        )
    }
}

/// Experimental slide-in for adjacent surface switches.
///
/// The gesture-free half of the two-finger-swipe request
/// (https://github.com/manaflow-ai/cmux/issues/1988): when ⌘⇧[ / ⌘⇧] (or a
/// trackpad tool bound to them) moves to the adjacent surface, the surface that
/// becomes visible slides in from the side it conceptually came from.
///
/// Deliberately presentation-only:
///
/// - It animates `transform.translation.x` on a layer, never a frame. The
///   portal derives terminal geometry from frames (`GeometryState` in
///   `GhosttyTerminalView` compares `frame`, so a frame nudge would bump
///   `geometryRevision` and schedule a portal reconcile for every animation
///   tick), and `TerminalSurface.applySurfaceSize` only reaches
///   `ghostty_surface_set_size` when the grid actually changes. A translation
///   therefore costs one compositing transform and never touches the PTY.
/// - It adds no animation keys for opacity. The surface content is a
///   Ghostty-owned `CAMetalLayer`; fading an ancestor forces an offscreen pass.
///
/// The navigation action *arms* a direction, and the first portal reveal that
/// follows *consumes* it, so unrelated reveals (workspace switches, window
/// restore, right-sidebar docks) stay still.
@MainActor
enum SurfaceSwitchSlideAnimation {
    enum Direction {
        /// Moving to the next surface: the arriving one comes from the right.
        case fromTrailing
        /// Moving to the previous surface: the arriving one comes from the left.
        case fromLeading

        var sign: CGFloat {
            switch self {
            case .fromTrailing: 1
            case .fromLeading: -1
            }
        }
    }

    /// Live-tunable while dogfooding, e.g.
    /// `defaults write com.cmuxterm.app.debug.slide cmux.surfaceSlide.offset -float 32`.
    private enum Key {
        static let enabled = "cmux.surfaceSlide.enabled"
        static let offset = "cmux.surfaceSlide.offset"
        static let duration = "cmux.surfaceSlide.duration"
    }

    /// How long an armed direction stays valid. The reveal normally lands in the
    /// same runloop turn; this only keeps a switch that never revealed anything
    /// from animating the next unrelated reveal.
    private static let armWindow: TimeInterval = 0.3

    private static var armedDirection: Direction?
    private static var armedAt: TimeInterval = 0

    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Key.enabled) != nil else { return true }
        return defaults.bool(forKey: Key.enabled)
    }

    private static var offset: CGFloat {
        let value = UserDefaults.standard.double(forKey: Key.offset)
        return value > 0 ? CGFloat(value) : 24
    }

    private static var duration: TimeInterval {
        let value = UserDefaults.standard.double(forKey: Key.duration)
        return value > 0 ? value : 0.14
    }

    /// Records the direction of a surface switch that is about to happen.
    static func arm(_ direction: Direction) {
        guard isEnabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        armedDirection = direction
        armedAt = ProcessInfo.processInfo.systemUptime
    }

    /// Takes the armed direction if one is still fresh.
    private static func consume() -> Direction? {
        guard let direction = armedDirection else { return nil }
        armedDirection = nil
        guard ProcessInfo.processInfo.systemUptime - armedAt <= armWindow else { return nil }
        return direction
    }

    /// Plays the slide on `layer` if the preceding switch armed a direction.
    ///
    /// `layer` should be clipped by its superlayer so the offset reads as an
    /// edge reveal rather than an overlap; the hosted view sets
    /// `masksToBounds` for exactly that reason.
    static func playIfArmed(on layer: CALayer?) {
        guard let layer, let direction = consume() else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = direction.sign * offset
        animation.toValue = 0
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        // Presentation-only: the model value stays 0, so nothing has to undo
        // this and an interrupted switch cannot leave a surface offset.
        layer.add(animation, forKey: "cmux.surfaceSlide")
    }
}
