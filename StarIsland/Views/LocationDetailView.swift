import SwiftUI
import MapKit

// MARK: - Location Detail View

/// Displays all records pinned to a single ``MemoryLocation``.
///
/// ```
/// ┌──────────────────────────────────┐
/// │  🏫 学校                         │
/// │  12 条记录                        │
/// │  首次 2026-01-15 · 最近 2026-06-20│
/// │                                  │
/// │  ●  23:57:13  📍学校  😊         │
/// │  │  今天在学校待到很晚              │
/// │  │                              │
/// │  ●  18:30:00  📍学校  😐         │
/// │  │  考试结束                      │
/// └──────────────────────────────────┘
/// ```
struct LocationDetailView: View {
    let location: MemoryLocation

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ── Header ────────────────────────────────────────
                headerView
                    .padding(.horizontal, AppTheme.spacing.xxxlarge)
                    .padding(.top, AppTheme.spacing.xxxlarge)
                    .padding(.bottom, AppTheme.spacing.medium)

                // ── Mini map preview ─────────────────────────────
                miniMap
                    .padding(.horizontal, AppTheme.spacing.xxxlarge)
                    .padding(.bottom, AppTheme.spacing.xlarge)

                Divider()
                    .padding(.horizontal, AppTheme.spacing.xxxlarge)

                // ── Records ──────────────────────────────────────
                if location.records.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(location.records.enumerated()),
                                id: \.element.id) { index, record in
                            NavigationLink(
                                destination: RecordDetailView(record: record)
                            ) {
                                TimelineCell(
                                    record: record,
                                    isLast: index == location.records.count - 1
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, AppTheme.spacing.large)
                }

                Spacer(minLength: AppTheme.spacing.huge)
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.small) {
            // ── Icon + name ──────────────────────────────────────
            HStack(spacing: AppTheme.spacing.small) {
                Text("📍")
                    .font(.title)
                Text(location.name)
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }

            // ── Stats ────────────────────────────────────────────
            Text("\(location.recordCount) 条记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("首次 \(location.firstDate.dayTitle) · 最近 \(location.latestDate.dayTitle)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Mini Map

    private var miniMap: some View {
        Map(
            position: .constant(.region(MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )))
        ) {
            Annotation(location.name, coordinate: location.coordinate, anchor: .bottom) {
                Text("📍")
                    .font(.system(size: 18))
            }
        }
        .mapStyle(.standard)
        .allowsHitTesting(false)
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius.large, style: .continuous))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppTheme.spacing.xlarge) {
            Spacer().frame(height: AppTheme.spacing.huge)
            Text("没有记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LocationDetailView(
            location: MemoryLocation(
                id: "school",
                name: "学校",
                latitude: 34.3416,
                longitude: 108.9398,
                recordCount: 3,
                firstDate: Date().addingTimeInterval(-86400 * 30),
                latestDate: Date(),
                records: [
                    Record(text: "今天在学校待到很晚。", mood: .tired, locationName: "学校"),
                    Record(text: "考试结束！", mood: .excited, locationName: "学校"),
                    Record(text: "午餐吃了食堂。", mood: .neutral, locationName: "学校"),
                ]
            )
        )
    }
}
