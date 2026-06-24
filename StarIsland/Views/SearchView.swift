import SwiftUI
import SwiftData

// MARK: - Search View

/// Full‑screen search interface.
///
/// Shows a ``SearchBarView`` at the top and live‑updating results below.
/// Results are rendered as ``TimelineCell`` entries so the timeline
/// aesthetic is preserved.
///
/// ## Phase 3.5 — Location integration
/// When the query matches a location name, a "地点" section offers to
/// open the **Map** tab focused on that pin.
struct SearchView: View {
    @Binding var selectedTab: AppTab
    @Binding var focusLocation: String?

    @Query(
        filter: #Predicate<Record> { !$0.isTrashed },
        sort: \Record.timestamp, order: .reverse
    )
    private var allRecords: [Record]

    @State private var query: String = ""

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // ── Search bar ─────────────────────────────────────────
            SearchBarView(text: $query, placeholder: "搜索文字、地点或心情")

            // ── Results ────────────────────────────────────────────
            if query.isEmpty {
                emptyPrompt
            } else if results.isEmpty && matchingLocations.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
    }

    // MARK: - Results

    private var results: [Record] {
        SearchService.search(query, among: allRecords)
    }

    /// Unique location names that contain the current query.
    private var matchingLocations: [String] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return [] }

        let allNames = Set(
            allRecords.compactMap(\.locationName).filter { !$0.isEmpty }
        )
        return allNames
            .filter { $0.localizedCaseInsensitiveContains(query) }
            .sorted()
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // ── Location matches ───────────────────────────────
                if !matchingLocations.isEmpty {
                    locationSection
                }

                // ── Record matches ─────────────────────────────────
                if !results.isEmpty {
                    recordSection
                }

                if results.isEmpty && !matchingLocations.isEmpty {
                    locationOnlyEmpty
                }
            }
            .padding(.vertical, AppTheme.spacing.large)
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.small) {
            Text("地点")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppTheme.spacing.xlarge)
                .padding(.bottom, AppTheme.spacing.xxsmall)

            ForEach(matchingLocations, id: \.self) { name in
                Button {
                    focusLocation = name
                    selectedTab = .map
                } label: {
                    HStack(spacing: AppTheme.spacing.medium) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.primary)
                            .frame(width: AppTheme.timeline.indicatorWidth)

                        VStack(alignment: .leading, spacing: AppTheme.spacing.xxxsmall) {
                            Text(name)
                                .font(.body)
                                .foregroundStyle(.primary)

                            Text("在地图上查看")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, AppTheme.spacing.xlarge)
                    .padding(.vertical, AppTheme.spacing.small)
                }
            }
        }
        .padding(.bottom, AppTheme.spacing.medium)
    }

    // MARK: - Record Section

    private var recordSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.small) {
            Text("记录")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppTheme.spacing.xlarge)

            ForEach(Array(results.enumerated()), id: \.element.id) { index, record in
                NavigationLink(destination: RecordDetailView(record: record)) {
                    TimelineCell(
                        record: record,
                        isLast: index == results.count - 1
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Empty States

    private var locationOnlyEmpty: some View {
        VStack(spacing: AppTheme.spacing.small) {
            Spacer().frame(height: AppTheme.spacing.xxlarge)
            Text("地点搜索结果中没有匹配的记录")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.spacing.xlarge) {
            Spacer()

            Text("🌌")
                .font(.system(size: 56))

            Text("StarIsland")
                .font(.title)
                .fontWeight(.semibold)

            Text("没有找到相关记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyPrompt: some View {
        VStack(spacing: AppTheme.spacing.xlarge) {
            Spacer()

            Text("🔍")
                .font(.system(size: 56))

            Text("StarIsland")
                .font(.title)
                .fontWeight(.semibold)

            Text("搜索文字、地点或心情")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SearchView(
            selectedTab: .constant(.search),
            focusLocation: .constant(nil)
        )
        .modelContainer(for: Record.self, inMemory: true)
    }
}
