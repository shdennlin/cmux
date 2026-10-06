import AppKit
import CmuxFoundation

/// Draws a top tab's activity bar with Core Animation, so the running sweep
/// runs in the render server and costs the main thread nothing per frame.
final class WorkspaceTopTabActivityBarLayerView: NSView {
    static let sweepAnimationKey = "workspaceTopTabActivityBarSweep"
    static let sweepDuration: CFTimeInterval = 1.4
    /// The highlight's width as a fraction of the bar.
    private static let highlightFraction: CGFloat = 0.38

    private let trackLayer = CALayer()
    private let highlightLayer = CAGradientLayer()
    private var state: TopTabActivityState = .running
    private var animatedWidth: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(trackLayer)
        highlightLayer.startPoint = CGPoint(x: 0, y: 0.5)
        highlightLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(highlightLayer)
        // Reduce Motion can change while the bar is up; follow it live.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(state: TopTabActivityState) {
        self.state = state
        updateColors()
        updateGeometry()
        updateAnimation()
    }

    override func layout() {
        super.layout()
        updateGeometry()
        updateAnimation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    @objc private func accessibilityDisplayOptionsDidChange(_ notification: Notification) {
        updateColors()
        updateAnimation()
    }

    private var sweeps: Bool {
        state == .running && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// The state's shared palette colour, resolved for the appearance it is
    /// drawn in; the sidebar rows use the same hexes.
    private var baseColor: NSColor {
        let state = state
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: state.hex(isDark: isDark)) ?? .systemGray
        }
    }

    private func updateColors() {
        var resolved = baseColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = baseColor.usingColorSpace(.sRGB) ?? baseColor
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // While sweeping, the track is a faint rail and the highlight is the
        // signal. Without a sweep (a solid state, or Reduce Motion) the track
        // itself is the signal at full strength.
        trackLayer.backgroundColor = resolved.withAlphaComponent(sweeps ? 0.28 : 1).cgColor
        highlightLayer.colors = [
            resolved.withAlphaComponent(0).cgColor,
            resolved.cgColor,
            resolved.withAlphaComponent(0).cgColor,
        ]
        highlightLayer.isHidden = !sweeps
        CATransaction.commit()
    }

    private func updateGeometry() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = bounds.height / 2
        trackLayer.frame = bounds
        highlightLayer.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width * Self.highlightFraction,
            height: bounds.height
        )
        CATransaction.commit()
    }

    /// Keeps the sweep in step with state, width and window. The animation is
    /// re-added whenever it is missing, because a view update can drop it.
    private func updateAnimation() {
        guard sweeps, window != nil, bounds.width > 0 else {
            highlightLayer.removeAnimation(forKey: Self.sweepAnimationKey)
            animatedWidth = 0
            return
        }
        let widthChanged = abs(animatedWidth - bounds.width) > 0.5
        if !widthChanged, highlightLayer.animation(forKey: Self.sweepAnimationKey) != nil { return }

        let highlightWidth = bounds.width * Self.highlightFraction
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        // From fully off the leading edge to fully off the trailing one.
        animation.fromValue = -highlightWidth
        animation.toValue = bounds.width
        animation.duration = Self.sweepDuration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
        highlightLayer.add(animation, forKey: Self.sweepAnimationKey)
        animatedWidth = bounds.width
    }
}
