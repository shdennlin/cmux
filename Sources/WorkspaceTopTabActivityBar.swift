import AppKit
import SwiftUI

/// The thin bar along a top tab's lower edge that says what its agent is doing:
/// a highlight sweeping across while it runs, a solid line while it needs the
/// person or has failed. A moving bar would read as "still busy", so only
/// running moves.
struct WorkspaceTopTabActivityBar: View {
    static let height: CGFloat = 2
    static let horizontalInset: CGFloat = 6

    let state: TopTabActivityState

    var body: some View {
        WorkspaceTopTabActivityBarRepresentable(state: state)
            .frame(height: Self.height)
            .padding(.horizontal, Self.horizontalInset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct WorkspaceTopTabActivityBarRepresentable: NSViewRepresentable {
    let state: TopTabActivityState

    func makeNSView(context: Context) -> WorkspaceTopTabActivityBarLayerView {
        let view = WorkspaceTopTabActivityBarLayerView(frame: .zero)
        view.configure(state: state)
        return view
    }

    func updateNSView(_ nsView: WorkspaceTopTabActivityBarLayerView, context: Context) {
        nsView.configure(state: state)
    }
}
