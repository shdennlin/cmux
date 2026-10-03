public import Foundation

/// Decides which destinations a sidebar metadata entry may carry.
///
/// The rule is enforced twice on purpose: the control socket refuses a
/// disallowed URL when `set_status` / `report_meta` stores one, and the row
/// refuses to draw one as a link if it reaches the view anyway. Both sides own
/// the same value so the two checks cannot drift — before this type they were
/// two literals tied together only by a comment, and relaxing one without the
/// other produced a URL that was stored and then silently not clickable.
///
/// Web destinations are always allowed. One more is: the app's own URL scheme,
/// so a row can carry a `cmux://workspace/<id>/surface/<id>` link back into
/// cmux itself. That stays narrow deliberately — admitting any scheme would let
/// a caller with control-socket access put a row in the sidebar that launches
/// an unrelated application's URL handler, which opening cmux's own navigation
/// links does not.
///
/// ```swift
/// let policy = SidebarMetadataURLPolicy(appScheme: AuthEnvironment.callbackScheme)
/// guard policy.allows(url) else { return }
/// ```
public struct SidebarMetadataURLPolicy: Sendable {
    /// This build's own URL scheme, which varies per app (`cmux`,
    /// `cmux-dev-plus`, ...); `nil` allows web destinations only.
    private let appScheme: String?

    /// Creates a policy that also admits one app scheme.
    ///
    /// - Parameter appScheme: The running app's own URL scheme, as the auth
    ///   callback scheme spells it. Case is ignored. `nil` or empty admits web
    ///   destinations only, which is the right default for a caller that
    ///   cannot resolve the scheme.
    public init(appScheme: String?) {
        let trimmed = appScheme?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appScheme = (trimmed?.isEmpty == false) ? trimmed?.lowercased() : nil
    }

    /// Whether a sidebar metadata entry may carry this destination.
    ///
    /// - Parameter url: The destination a caller supplied.
    /// - Returns: `true` for `http`, `https`, and this build's own scheme.
    public func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "http" || scheme == "https" { return true }
        return appScheme != nil && scheme == appScheme
    }

    /// The error a caller sees when a destination is refused.
    ///
    /// - Parameter rawURL: The destination as the caller spelled it.
    /// - Returns: A message naming what is accepted, including the app scheme
    ///   when one is known, so the caller is not left guessing.
    public func rejectionMessage(rawURL: String) -> String {
        guard let appScheme else {
            return "ERROR: Invalid metadata URL '\(rawURL)' — expected http(s) URL"
        }
        return "ERROR: Invalid metadata URL '\(rawURL)' — expected an http(s) or \(appScheme):// URL"
    }
}
