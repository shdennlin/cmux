import CmuxFoundation
import CmuxCloud
import Foundation
import SwiftUI

extension AttributedString {
    /// Keeps the destinations ``SidebarMetadataURLPolicy`` admits — web, plus
    /// this build's own scheme — and gives selected-row links a readable color.
    func applyingSidebarRowLinkPolicy(activeForegroundColor: Color?) -> AttributedString {
        transformingAttributes(
            \.link,
            \.foregroundColor
        ) { link, foregroundColor in
            guard let url = link.value else { return }
            guard SidebarMetadataURLPolicy(
                appScheme: AuthEnvironment.callbackScheme
            ).allows(url) else {
                link.value = nil
                return
            }
            if let activeForegroundColor {
                foregroundColor.value = activeForegroundColor
            }
        }
    }
}
