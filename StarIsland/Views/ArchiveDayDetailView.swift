import SwiftUI
import SwiftData

// MARK: - Archive Day Detail View

/// Displays every record (time‑slice) for a single calendar day.
///
/// ```
/// ┌──────────────────────────────────┐
/// │  2026年06月24日 星期三             │
/// │  [在时间线中查看]                  │
/// │                                  │
/// │  ●  23:57:13  📍家  😊           │
/// │  │  日落很美                      │
/// │  │                              │
/// │  ●  18:30:00                     │
/// │  │  跑完步                          │
/// └──────────────────────────────────┘
/// ```
///
/// Tap "在时间线中查看" to switch to the **Timeline** tab and auto‑scroll
/// to this day's section (see ``ArchiveView`` → ``TimelineView`` linkage).
struct ArchiveDayDetailView: View {
    let date: Date

    /// Passed through from the parent so we can switch tabs.
    @Binding var selectedTab: AppTab
    @Binding var scrollToDate: Date?

    @Environment(\.modelContext) private var context

    @Query private var records: [Record]

    // MARK: - Init

    init(date: Date,
         selectedTab: Binding<AppTab>,
         scrollToDate: Binding<Date?>) {
        self.date = date
        _selectedTab = selectedTab
        _scrollToDate = scrollToDate

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            _records = Query(filter: #Predicate { _ in false })
            return
        }

        _records = Query(
            filter: #Predicate<Record> { record in
                record.timestamp >= dayStart && record.timestamp < dayEnd && !record.isTrashed
            },
            sort: \Record.timestamp,
            order: .reverse
        )
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ── Header ────────────────────────────────────────
                headerView
                    .padding(.horizontal, AppTheme.spacing.xxxlarge)
                    .padding(.top, AppTheme.spacing.xxxlarge)

                // ── Timeline ──────────────────────────────────────
                if records.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            NavigationLink(
                                destination: RecordDetailView(record: record)
                            ) {
                                TimelineCell(
                                    record: record,
                                    isLast: index == records.count - 1
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
        .toolbar { toolbarContent }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xsmall) {
            Text(date.dayTitle)
                .font(.largeTitle)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Text(date.weekday)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppTheme.spacing.xlarge) {
            Spacer().frame(height: AppTheme.spacing.huge)
            Text("📄")
                .font(.system(size: 48))
            Text("这一天没有记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                scrollToDate = date
                selectedTab = .timeline
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .foregroundStyle(.primary)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ArchiveDayDetailView(
            date: Date(),
            selectedTab: .constant(.archive),
            scrollToDate: .constant(nil)
        )
        .modelContainer(for: Record.self, inMemory: true)
    }
}
