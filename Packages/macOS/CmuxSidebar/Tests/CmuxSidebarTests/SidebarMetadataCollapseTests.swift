import Testing

@testable import CmuxSidebar

@Suite struct SidebarMetadataCollapseTests {
    /// Six agent rows under the status-entry limit of 3: collapsed shows the
    /// first three and offers the toggle.
    @Test func collapsedStackClipsToTheLimitAndOffersTheToggle() {
        let collapse = SidebarMetadataCollapse(
            totalCount: 6,
            collapsedLimit: 3,
            isExpanded: false,
            expandsAll: false
        )
        #expect(collapse.visibleCount == 3)
        #expect(collapse.showsToggle)
    }

    /// Expanding by hand keeps the toggle so Show less stays reachable.
    @Test func expandedStackKeepsTheToggle() {
        let collapse = SidebarMetadataCollapse(
            totalCount: 6,
            collapsedLimit: 3,
            isExpanded: true,
            expandsAll: false
        )
        #expect(collapse.visibleCount == 6)
        #expect(collapse.showsToggle)
    }

    /// `sidebar.expandAllCustomMetadata`: every row is drawn and the toggle
    /// is withdrawn, regardless of the per-row expansion state.
    @Test(arguments: [false, true])
    func expandsAllDrawsEveryRowWithoutAToggle(isExpanded: Bool) {
        let collapse = SidebarMetadataCollapse(
            totalCount: 6,
            collapsedLimit: 3,
            isExpanded: isExpanded,
            expandsAll: true
        )
        #expect(collapse.visibleCount == 6)
        #expect(!collapse.showsToggle)
    }

    /// A stack that fits never offers the toggle, whatever the other inputs.
    @Test(arguments: [
        (0, false, false),
        (1, true, false),
        (3, false, false),
        (3, true, false),
        (3, false, true),
        (3, true, true),
    ] as [(Int, Bool, Bool)])
    func stackWithinTheLimitHasNoToggle(
        totalCount: Int,
        isExpanded: Bool,
        expandsAll: Bool
    ) {
        let collapse = SidebarMetadataCollapse(
            totalCount: totalCount,
            collapsedLimit: 3,
            isExpanded: isExpanded,
            expandsAll: expandsAll
        )
        #expect(collapse.visibleCount == totalCount)
        #expect(!collapse.showsToggle)
    }

    /// The markdown-block stack collapses at 1, so a second block is what
    /// first earns the Show more details toggle.
    @Test func markdownBlockLimitOfOne() {
        let single = SidebarMetadataCollapse(
            totalCount: 1,
            collapsedLimit: 1,
            isExpanded: false,
            expandsAll: false
        )
        #expect(single.visibleCount == 1)
        #expect(!single.showsToggle)

        let pair = SidebarMetadataCollapse(
            totalCount: 2,
            collapsedLimit: 1,
            isExpanded: false,
            expandsAll: false
        )
        #expect(pair.visibleCount == 1)
        #expect(pair.showsToggle)

        let pairExpandingAll = SidebarMetadataCollapse(
            totalCount: 2,
            collapsedLimit: 1,
            isExpanded: false,
            expandsAll: true
        )
        #expect(pairExpandingAll.visibleCount == 2)
        #expect(!pairExpandingAll.showsToggle)
    }

    @Test func visibleItemsReturnsTheLeadingSlice() {
        let collapse = SidebarMetadataCollapse(
            totalCount: 5,
            collapsedLimit: 3,
            isExpanded: false,
            expandsAll: false
        )
        #expect(collapse.visibleItems(of: ["a", "b", "c", "d", "e"]) == ["a", "b", "c"])
    }

    /// A shorter collection than the one the value was resolved for yields
    /// all of it instead of trapping on `prefix`.
    @Test func visibleItemsToleratesAShorterCollection() {
        let collapse = SidebarMetadataCollapse(
            totalCount: 6,
            collapsedLimit: 3,
            isExpanded: true,
            expandsAll: false
        )
        #expect(collapse.visibleItems(of: ["a", "b"]) == ["a", "b"])
    }

    /// Negative inputs read as zero rather than producing a negative count.
    @Test func negativeInputsClampToZero() {
        let collapse = SidebarMetadataCollapse(
            totalCount: -4,
            collapsedLimit: -1,
            isExpanded: false,
            expandsAll: false
        )
        #expect(collapse.visibleCount == 0)
        #expect(!collapse.showsToggle)
    }
}
