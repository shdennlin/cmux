import Foundation

/// Where one workspace row draws its Select-Workspace-by-number shortcut.
///
/// Both sidebar renderers (the AppKit table cell and the SwiftUI row) resolve
/// through this type so the two cannot disagree about which hint shows.
struct SidebarWorkspaceNumberHint: Equatable {
    /// Always-visible label before the title (`sidebar.alwaysShowWorkspaceNumbers`).
    let leadingLabel: String?
    /// Modifier-hold pill on the row's top trailing edge.
    let trailingPill: String?

    static func resolve(
        showsModifierHints: Bool,
        alwaysShowsPill: Bool,
        alwaysShowsNumbers: Bool,
        digit: Int?,
        modifierSymbol: String
    ) -> SidebarWorkspaceNumberHint {
        guard let digit else { return SidebarWorkspaceNumberHint(leadingLabel: nil, trailingPill: nil) }
        let text = "\(modifierSymbol)\(digit)"
        // The always-visible number replaces the pill instead of doubling it.
        if alwaysShowsNumbers {
            return SidebarWorkspaceNumberHint(leadingLabel: text, trailingPill: nil)
        }
        return SidebarWorkspaceNumberHint(
            leadingLabel: nil,
            trailingPill: (showsModifierHints || alwaysShowsPill) ? text : nil
        )
    }
}
