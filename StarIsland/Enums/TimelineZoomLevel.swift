import Foundation

// MARK: - Timeline Zoom Level

/// Zoom levels for the timeline's multi‑scale viewing system.
///
/// - ``day``:   Each record as a separate row (default, current behaviour).
/// - ``week``:  Current week overview — one column per day.
/// - ``month``: Current month calendar — heatmap cells by day.
/// - ``year``:  GitHub‑style contribution grid (via ``ContributionGridView``).
///
/// Persisted via `@AppStorage`; restored on next launch.
enum TimelineZoomLevel: String, CaseIterable, Sendable {
    case day
    case week
    case month
    case year
}
