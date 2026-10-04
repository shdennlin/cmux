import Foundation
import Testing
@testable import CmuxPanes

@Suite struct TopTabConversionPlannerTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()
    let p1 = UUID(), p2 = UUID()

    @Test func singleSurfacePanesNeedNoNewTabs() {
        let plan = TopTabConversionPlanner.split(panesInSpatialOrder: [
            .init(paneId: p1, surfaceIds: [a], selectedSurfaceId: a),
            .init(paneId: p2, surfaceIds: [b], selectedSurfaceId: b),
        ])
        #expect(plan.keep == [p1: a, p2: b])
        #expect(plan.newTabs.isEmpty)
    }

    @Test func extraSurfacesBecomeTabsInPaneThenTabOrder() {
        let plan = TopTabConversionPlanner.split(panesInSpatialOrder: [
            .init(paneId: p1, surfaceIds: [a, b, c], selectedSurfaceId: b),
            .init(paneId: p2, surfaceIds: [d, e], selectedSurfaceId: d),
        ])
        #expect(plan.keep == [p1: b, p2: d])
        #expect(plan.newTabs == [a, c, e])
    }

    @Test func everySurfaceIsAccountedForExactlyOnce() {
        let panes: [TopTabPaneInput] = [
            .init(paneId: p1, surfaceIds: [a, b, c], selectedSurfaceId: c),
            .init(paneId: p2, surfaceIds: [d, e], selectedSurfaceId: e),
        ]
        let plan = TopTabConversionPlanner.split(panesInSpatialOrder: panes)
        let accounted = Array(plan.keep.values) + plan.newTabs
        #expect(Set(accounted) == Set(panes.flatMap(\.surfaceIds)))
        #expect(accounted.count == 5)
    }

    @Test func mergeKeepsSelectedAndMovesOthersInOrder() {
        let plan = TopTabConversionPlanner.merge(topTabIds: [a, b, c], selected: b)
        #expect(plan.stay == b)
        #expect(plan.newWorkspaces == [a, c])
    }
}
