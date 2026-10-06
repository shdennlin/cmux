import Foundation
import Testing
@testable import CmuxControlSocket

/// A scriptable ``ControlCommandContext`` for driving the tab-state
/// coordinator domain without the app target.
@MainActor
final class FakeTabStateControlCommandContext: ControlCommandContext {
    var setResolution: ControlTabStateResolution = .tabManagerUnavailable
    var clearResolution: ControlTabStateResolution = .tabManagerUnavailable
    var listResolution: ControlTabStateListResolution = .tabManagerUnavailable

    var setCalls: [(workspaceID: UUID?, surfaceID: UUID?, state: ControlTabState)] = []
    var clearCalls: [(workspaceID: UUID?, surfaceID: UUID?)] = []
    var listCalls: [UUID?] = []

    func controlSetTabState(
        routing: ControlRoutingSelectors,
        workspaceID: UUID?,
        surfaceID: UUID?,
        state: ControlTabState
    ) -> ControlTabStateResolution {
        setCalls.append((workspaceID, surfaceID, state))
        return setResolution
    }

    func controlClearTabState(
        routing: ControlRoutingSelectors,
        workspaceID: UUID?,
        surfaceID: UUID?
    ) -> ControlTabStateResolution {
        clearCalls.append((workspaceID, surfaceID))
        return clearResolution
    }

    func controlListTabStates(
        routing: ControlRoutingSelectors,
        workspaceID: UUID?
    ) -> ControlTabStateListResolution {
        listCalls.append(workspaceID)
        return listResolution
    }
}

@MainActor
@Suite("ControlCommandCoordinator tab-state domain")
struct ControlCommandCoordinatorTabStateTests {
    func makeCoordinator() -> (ControlCommandCoordinator, FakeTabStateControlCommandContext) {
        let context = FakeTabStateControlCommandContext()
        let coordinator = ControlCommandCoordinator(context: context)
        return (coordinator, context)
    }

    func request(_ method: String, _ params: [String: JSONValue] = [:]) -> ControlRequest {
        ControlRequest(id: .int(1), method: method, params: params)
    }

    @Test func setPassesTheStateAndTargetsAcrossTheSeam() throws {
        let (coordinator, context) = makeCoordinator()
        let workspaceID = UUID()
        let surfaceID = UUID()
        context.setResolution = .applied(workspaceID: workspaceID, surfaceID: surfaceID, state: .running)

        let result = try #require(coordinator.handle(request("surface.tab_state.set", [
            "state": .string("running"),
            "workspace_id": .string(workspaceID.uuidString),
            "surface_id": .string(surfaceID.uuidString),
        ])))

        #expect(context.setCalls.count == 1)
        #expect(context.setCalls.first?.workspaceID == workspaceID)
        #expect(context.setCalls.first?.surfaceID == surfaceID)
        #expect(context.setCalls.first?.state == .running)
        guard case .ok(.object(let payload)) = result else {
            Issue.record("expected ok payload, got \(result)")
            return
        }
        #expect(payload["state"] == .string("running"))
        #expect(payload["surface_id"] == .string(surfaceID.uuidString))
        #expect(payload["workspace_id"] == .string(workspaceID.uuidString))
    }

    /// The CLI spells it with a hyphen; the wire value uses an underscore.
    @Test(arguments: ["needs-input", "needs_input", "NEEDS-INPUT"])
    func setAcceptsEitherSpellingOfNeedsInput(raw: String) throws {
        let (coordinator, context) = makeCoordinator()
        let surfaceID = UUID()
        context.setResolution = .applied(workspaceID: UUID(), surfaceID: surfaceID, state: .needsInput)

        let result = try #require(coordinator.handle(request("surface.tab_state.set", [
            "state": .string(raw),
            "surface_id": .string(surfaceID.uuidString),
        ])))

        #expect(context.setCalls.first?.state == .needsInput)
        guard case .ok(.object(let payload)) = result else {
            Issue.record("expected ok payload, got \(result)")
            return
        }
        #expect(payload["state"] == .string("needs_input"))
    }

    /// An unknown state never reaches the app, so a typo cannot paint a bar.
    @Test(arguments: ["busy", "", "auto"])
    func setRejectsUnknownStatesBeforeTheApp(raw: String) throws {
        let (coordinator, context) = makeCoordinator()

        let result = try #require(coordinator.handle(request("surface.tab_state.set", [
            "state": .string(raw),
        ])))

        #expect(context.setCalls.isEmpty)
        guard case .err(let code, _, _) = result else {
            Issue.record("expected an error, got \(result)")
            return
        }
        #expect(code == "invalid_params")
    }

    @Test func setWithoutAStateIsRejected() throws {
        let (coordinator, context) = makeCoordinator()
        let result = try #require(coordinator.handle(request("surface.tab_state.set")))
        #expect(context.setCalls.isEmpty)
        guard case .err(let code, _, _) = result else {
            Issue.record("expected an error, got \(result)")
            return
        }
        #expect(code == "invalid_params")
    }

    @Test func clearHandsBackToTheBuiltInState() throws {
        let (coordinator, context) = makeCoordinator()
        let surfaceID = UUID()
        context.clearResolution = .applied(workspaceID: UUID(), surfaceID: surfaceID, state: nil)

        let result = try #require(coordinator.handle(request("surface.tab_state.clear", [
            "surface_id": .string(surfaceID.uuidString),
        ])))

        #expect(context.clearCalls.first?.surfaceID == surfaceID)
        guard case .ok(.object(let payload)) = result else {
            Issue.record("expected ok payload, got \(result)")
            return
        }
        #expect(payload["state"] == .null)
    }

    @Test func listShapesEachEntry() throws {
        let (coordinator, context) = makeCoordinator()
        let workspaceID = UUID()
        let first = UUID()
        let second = UUID()
        context.listResolution = .listed(workspaceID: workspaceID, entries: [
            ControlTabStateEntry(surfaceID: first, state: .error),
            ControlTabStateEntry(surfaceID: second, state: .idle),
        ])

        let result = try #require(coordinator.handle(request("surface.tab_state.list")))

        guard case .ok(.object(let payload)) = result,
              case .array(let entries)? = payload["entries"] else {
            Issue.record("expected ok payload with entries, got \(result)")
            return
        }
        #expect(payload["workspace_id"] == .string(workspaceID.uuidString))
        #expect(entries.count == 2)
        guard case .object(let firstEntry) = entries[0], case .object(let secondEntry) = entries[1] else {
            Issue.record("expected object entries")
            return
        }
        #expect(firstEntry["surface_id"] == .string(first.uuidString))
        #expect(firstEntry["state"] == .string("error"))
        #expect(secondEntry["state"] == .string("idle"))
    }

    @Test func unknownTargetsReportNotFound() throws {
        let (coordinator, context) = makeCoordinator()
        context.setResolution = .notFound
        let result = try #require(coordinator.handle(request("surface.tab_state.set", [
            "state": .string("error"),
            "surface_id": .string(UUID().uuidString),
        ])))
        guard case .err(let code, _, _) = result else {
            Issue.record("expected an error, got \(result)")
            return
        }
        #expect(code == "not_found")
    }
}
