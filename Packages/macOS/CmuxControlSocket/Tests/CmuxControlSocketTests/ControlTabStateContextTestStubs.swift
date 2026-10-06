import Foundation
@testable import CmuxControlSocket

// Benign default implementations of the tab-state domain seam, so a test fake
// that conforms to the full `ControlCommandContext` umbrella only has to
// implement the domain it actually exercises.

extension ControlTabStateContext {
    func controlSetTabState(
        routing: ControlRoutingSelectors,
        workspaceID: UUID?,
        surfaceID: UUID?,
        state: ControlTabState
    ) -> ControlTabStateResolution { .tabManagerUnavailable }

    func controlClearTabState(
        routing: ControlRoutingSelectors,
        workspaceID: UUID?,
        surfaceID: UUID?
    ) -> ControlTabStateResolution { .tabManagerUnavailable }

    func controlListTabStates(
        routing: ControlRoutingSelectors,
        workspaceID: UUID?
    ) -> ControlTabStateListResolution { .tabManagerUnavailable }
}
