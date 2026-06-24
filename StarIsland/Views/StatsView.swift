import SwiftUI
import SwiftData

// MARK: - Stats View

/// Apple Health / Screen Time inspired summary page.
///
/// No charts, no graphs.  Just large numbers with terse labels and
/// generous whitespace.
struct StatsView: View {
    @Environment(\.modelContext) private var context

    @State private var stats: AppStats = .zero

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.large) {
                // ── Header ────────────────────────────────────────
                headerView

                // ── Cards ─────────────────────────────────────────
                LazyVStack(spacing: AppTheme.spacing.large) {
                    StatsCardView(
                        title: "总记录数",
                        value: "\(stats.recordCount)"
                    )

                    if stats.photoCount > 0 {
                        StatsCardView(
                            title: "总照片数",
                            value: "\(stats.photoCount)"
                        )
                    }

                    StatsCardView(
                        title: "最长连续记录",
                        value: "\(stats.longestStreak) 天"
                    )

                    if let first = stats.firstRecordDate {
                        StatsCardView(
                            title: "第一条记录",
                            value: first.dayTitle,
                            subtitle: first.weekday
                        )
                    }

                    if let last = stats.latestRecordDate {
                        StatsCardView(
                            title: "最近记录",
                            value: last.dayTitle,
                            subtitle: last.weekday
                        )
                    }

                    // ── Phase 3.5: Location stats ─────────────────

                    if stats.totalLocations > 0 {
                        StatsCardView(
                            title: "总地点数",
                            value: "\(stats.totalLocations) 个"
                        )
                    }

                    if let location = stats.topLocation {
                        StatsCardView(
                            title: "最常地点",
                            value: location
                        )
                    }

                    if let latest = stats.latestLocation {
                        StatsCardView(
                            title: "最近地点",
                            value: latest
                        )
                    }

                    if stats.farthestDistanceKm > 0 {
                        StatsCardView(
                            title: "最远距离",
                            value: String(
                                format: "%.1f km",
                                stats.farthestDistanceKm
                            )
                        )
                    }

                    // ── Mood ───────────────────────────────────────
                    if let mood = stats.topMood {
                        StatsCardView(
                            title: "最常心情",
                            value: "\(mood.emoji)  \(mood.title)"
                        )
                    }

                    if stats.recordCount > 0 {
                        StatsCardView(
                            title: "平均每天",
                            value: String(format: "%.1f 条", stats.averagePerDay)
                        )
                    }
                }
            }
            .padding(AppTheme.spacing.xxxlarge)
        }
        .background(Color(.systemBackground))
        .navigationTitle("统计")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadStats)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xxsmall) {
            Text("📊")
                .font(.system(size: 36))
                .padding(.bottom, AppTheme.spacing.small)

            Text("统计")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
        }
        .padding(.bottom, AppTheme.spacing.small)
    }

    // MARK: - Data

    private func loadStats() {
        stats = StatsService.compute(context: context)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        StatsView()
            .modelContainer(for: Record.self, inMemory: true)
    }
}
