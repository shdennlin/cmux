public import Foundation

/// One pane of the visible split layout, as the top tab conversion sees it.
public struct TopTabPaneInput: Equatable, Sendable {
    public var paneId: UUID
    public var surfaceIds: [UUID]
    public var selectedSurfaceId: UUID

    public init(paneId: UUID, surfaceIds: [UUID], selectedSurfaceId: UUID) {
        self.paneId = paneId
        self.surfaceIds = surfaceIds
        self.selectedSurfaceId = selectedSurfaceId
    }
}

/// Turning top tabs on: which surface each pane keeps, and which surfaces
/// become their own single-pane top tabs, in order.
public struct TopTabSplitPlan: Equatable, Sendable {
    public var keep: [UUID: UUID]
    public var newTabs: [UUID]

    public init(keep: [UUID: UUID], newTabs: [UUID]) {
        self.keep = keep
        self.newTabs = newTabs
    }
}

/// Turning top tabs off: the tab that stays in the workspace, and the tabs
/// that move to new workspaces directly below it, in order.
public struct TopTabMergePlan: Equatable, Sendable {
    public var stay: UUID
    public var newWorkspaces: [UUID]

    public init(stay: UUID, newWorkspaces: [UUID]) {
        self.stay = stay
        self.newWorkspaces = newWorkspaces
    }
}

/// Decides how surfaces move when the top tabs setting changes. Pure: it
/// never touches panels, controllers or processes.
public enum TopTabConversionPlanner {
    /// The top tab model allows one surface per pane: each pane keeps its
    /// selected surface and every other surface becomes its own tab,
    /// ordered by pane (spatial order) then by position in the pane.
    public static func split(panesInSpatialOrder panes: [TopTabPaneInput]) -> TopTabSplitPlan {
        var keep: [UUID: UUID] = [:]
        var newTabs: [UUID] = []
        for pane in panes {
            keep[pane.paneId] = pane.selectedSurfaceId
            newTabs += pane.surfaceIds.filter { $0 != pane.selectedSurfaceId }
        }
        return TopTabSplitPlan(keep: keep, newTabs: newTabs)
    }

    /// The single-layout model has one split tree per workspace, so every
    /// tab but the selected one moves to its own workspace to keep its layout.
    public static func merge(topTabIds: [UUID], selected: UUID) -> TopTabMergePlan {
        TopTabMergePlan(stay: selected, newWorkspaces: topTabIds.filter { $0 != selected })
    }
}
