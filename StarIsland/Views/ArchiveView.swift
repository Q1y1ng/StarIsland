import SwiftUI
import SwiftData

// MARK: - Archive View

/// Year‑over‑year contribution heatmap à la GitHub.
///
/// ## Layout
///
/// ```
/// ┌─────────────────────────────────────┐
/// │  2026                                │
/// │  365 天  ·  245 条记录  ·  47 天连续  │
/// │                                     │
/// │  <  2026  >                         │
/// │                                     │
/// │  一  ■■■■□■■                        │
/// │  三  ■■□■■■■                        │
/// │  五  □■■■■■□                        │
/// │                                     │
/// │  少                   多             │
/// └─────────────────────────────────────┘
/// ```
///
/// Tapping a day pushes ``ArchiveDayDetailView``.  From there the user
/// can jump to the Timeline and scroll to that exact date.
struct ArchiveView: View {
    @Binding var selectedTab: AppTab
    @Binding var scrollToDate: Date?

    @Environment(\.modelContext) private var context

    @State private var currentYear: Int = Calendar.current.component(.year, from: Date())
    @State private var weeks: [WeekInfo] = []
    @State private var days: [CalendarDayInfo] = []
    @State private var totalRecords: Int = 0
    @State private var continuousDays: Int = 0

    @State private var selectedDay: Date?

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ── Header ────────────────────────────────────────
                archiveHeader
                    .padding(.horizontal, AppTheme.spacing.xxxlarge)
                    .padding(.top, AppTheme.spacing.xxxlarge)
                    .padding(.bottom, AppTheme.spacing.xxlarge)

                // ── Year picker ────────────────────────────────────
                YearPickerView(currentYear: $currentYear)
                    .padding(.horizontal, AppTheme.spacing.xxxlarge)
                    .padding(.bottom, AppTheme.spacing.xxlarge)

                // ── Contribution grid ──────────────────────────────
                ContributionGridView(
                    weeks: weeks,
                    year: currentYear,
                    onTapDay: { date in
                        selectedDay = date
                    }
                )
                .padding(.horizontal, AppTheme.spacing.xxxlarge)
                .padding(.bottom, AppTheme.spacing.small)

                // ── Legend ─────────────────────────────────────────
                legend
                    .padding(.horizontal, AppTheme.spacing.xxxlarge)

                // ── Spacer for scroll breathing ────────────────────
                Spacer(minLength: AppTheme.spacing.huge)
            }
        }
        .navigationTitle("回顾")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
        .navigationDestination(item: $selectedDay) { date in
            ArchiveDayDetailView(
                date: date,
                selectedTab: $selectedTab,
                scrollToDate: $scrollToDate
            )
        }
        .onAppear(perform: loadData)
        .onChange(of: currentYear) { _, _ in loadData() }
    }

    // MARK: - Header

    private var archiveHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.medium) {
            // ── Current year ──────────────────────────────────────
            Text("\(currentYear)")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.primary)

            // ── Summary line ──────────────────────────────────────
            HStack(spacing: AppTheme.spacing.medium) {
                let calendar = Calendar.current
                let daysCount = calendar.range(
                    of: .day, in: .year,
                    for: calendar.date(from: DateComponents(year: currentYear))!
                )?.count ?? 365

                statChip("\(daysCount) 天")
                dotSeparator
                statChip("\(totalRecords) 条记录")
                dotSeparator
                statChip("\(continuousDays) 天连续")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var dotSeparator: some View {
        Text("·")
            .foregroundStyle(.tertiary)
    }

    private func statChip(_ text: String) -> Text {
        Text(text)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: AppTheme.spacing.small) {
            Text("少")
                .font(.caption)
                .foregroundStyle(.tertiary)

            ForEach(0 ..< 4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(heatmapSwatch(for: level))
                    .frame(
                        width: AppTheme.heatmap.cellSize,
                        height: AppTheme.heatmap.cellSize
                    )
            }

            Text("多")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func heatmapSwatch(for level: Int) -> Color {
        switch level {
        case 0: return .primary.opacity(0.05)
        case 1: return .primary.opacity(0.15)
        case 2: return .primary.opacity(0.30)
        default: return .primary.opacity(0.55)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        let counts = CalendarService.queryRecordCounts(for: currentYear, context: context)

        let calendar = Calendar.current
        guard let yearStart = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1))
        else { return }
        let daysInYear = calendar.range(of: .day, in: .year, for: yearStart)?.count ?? 365

        var allDays: [CalendarDayInfo] = []
        for offset in 0 ..< daysInYear {
            guard let d = calendar.date(byAdding: .day, value: offset, to: yearStart)
            else { continue }
            let dayStart = calendar.startOfDay(for: d)
            let count = counts[dayStart] ?? 0
            allDays.append(CalendarDayInfo(date: dayStart, count: count))
        }

        days = allDays
        totalRecords = CalendarService.totalRecordCount(days: allDays)
        continuousDays = CalendarService.currentStreak(days: allDays)
        weeks = CalendarService.generateYear(currentYear, recordCounts: counts)
    }
}

// MARK: - Extension for navigationDestination(item:)

/// Enables `.navigationDestination(item: $selectedDay)` with a Date value.
extension Date: @retroactive Identifiable {
    public var id: String { "\(timeIntervalSince1970)" }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ArchiveView(
            selectedTab: .constant(.archive),
            scrollToDate: .constant(nil)
        )
        .modelContainer(for: Record.self, inMemory: true)
    }
}
