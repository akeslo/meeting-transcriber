# Dashboard + Stats Merge

**Date:** 2026-05-23  
**Status:** Approved

## Goal

Remove the "Stats" sidebar item. Fold all statistics content into the Dashboard view as a new section below "Recent Activity". Delete `StatsView.swift`.

## Approach

Flatten — move all stat logic directly into `DashboardView`. No intermediate subview kept.

## Files Changed

| File | Change |
|------|--------|
| `Sources/DashboardWindow/SidebarView.swift` | Remove `NavItem.stats` case |
| `Sources/DashboardWindow/DashboardWindowContent.swift` | Remove `case .stats:` branch |
| `Sources/DashboardWindow/DashboardView.swift` | Add `@Query`, stat computed vars, `statCard()`, `activitySection`, statistics section in body |
| `Sources/DashboardWindow/StatsView.swift` | **Deleted** |

## DashboardView Changes

### Data
Add `@Query private var allSessions: [RecordingSession]` to `DashboardView`. `RecentActivitySection` keeps its own internal `@Query` — no interface change to that private struct.

### Computed properties (moved from StatsView)
- `completedSessions: [RecordingSession]`
- `totalHours: Double`
- `uniqueSpeakers: Int`
- `mostUsedApp: String?`
- `protocolRate: Double`
- `thisMonthCount: Int`
- `avgDurationMinutes: Double`
- `monthlyActivity: [String: Int]`

### Helpers (moved from StatsView)
- `statCard(icon:title:value:subtitle:)` — `@ViewBuilder` private func
- `activitySection` — computed `some View`

### Body layout (bottom of scroll)
```
VStack(alignment: .leading, spacing: 20) {
    StatusCard + QuickControls/AmbientLevel row   // existing
    RecentActivitySection                          // existing
    statisticsSection                              // new — "Statistics" heading + 3-col grid + bar chart
}
```

## NavItem

Remove `.stats`. Remaining cases: `.dashboard`, `.library`, `.settings`.  
`SidebarView` iterates `NavItem.allCases` — no other change needed.

## Visual Result

Dashboard scrolls through: status card row → recent activity → statistics grid → activity bar chart. Single nav item replaces two.

## Not In Scope

- No redesign of card styles or layout proportions
- No new statistics added
- `RecentActivitySection` interface unchanged
