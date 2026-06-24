import SwiftUI

// MARK: - Contribution Grid View

/// GitHub‑style contribution heatmap.
///
/// Layout (horizontal scroll):
/// ```
/// 一  ■■■■□■■
/// 三  ■■□■■■■
/// 五  □■■■■■□
///      ← weeks →
/// ```
///
/// Colours are derived from `Color.primary.opacity(...)` — no custom colours.
///
/// | Count | Opacity |
/// |---|---|
/// | 0 | 0.05 |
/// | 1–2 | 0.15 |
/// | 3–5 | 0.30 |
/// | 6+ | 0.55 |
struct ContributionGridView: View {
    let weeks: [WeekInfo]
    let year: Int
    var onTapDay: ((Date) -> Void)?

    // MARK: - Constants

    private let cellSize:   CGFloat = AppTheme.heatmap.cellSize
    private let cellSpacing: CGFloat = AppTheme.heatmap.cellSpacing

    // MARK: - Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: cellSpacing) {
                // ── Weekday labels ────────────────────────────────────
                weekdayLabelsColumn

                // ── Week columns ──────────────────────────────────────
                ForEach(weeks) { week in
                    VStack(spacing: cellSpacing) {
                        ForEach(0 ..< 7, id: \.self) { dayIndex in
                            Group {
                                if let day = week.days[dayIndex] {
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius.small)
                                        .fill(heatmapColor(for: day.count))
                                        .frame(width: cellSize, height: cellSize)
                                        .contentShape(Rectangle())
                                        .onTapGesture { onTapDay?(day.date) }
                                } else {
                                    Color.clear
                                        .frame(width: cellSize, height: cellSize)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, AppTheme.spacing.small)
        }
    }

    // MARK: - Weekday Labels

    private var weekdayLabelsColumn: some View {
        VStack(spacing: cellSpacing) {
            // Mon / Wed / Fri only — keeps it minimal
            ForEach([1, 3, 5], id: \.self) { weekdayIndex in
                Text(weekdayLabel(for: weekdayIndex))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(height: cellSize)
            }
        }
        .padding(.trailing, AppTheme.spacing.xxsmall)
    }

    private func weekdayLabel(for index: Int) -> String {
        // index: 0=Mon, 1=Tue, …, 6=Sun
        ["一", "二", "三", "四", "五", "六", "日"][index]
    }

    // MARK: - Heatmap Colour

    private func heatmapColor(for count: Int) -> Color {
        switch count {
        case 0:     return .primary.opacity(0.05)
        case 1, 2:  return .primary.opacity(0.15)
        case 3...5: return .primary.opacity(0.30)
        default:    return .primary.opacity(0.55)
        }
    }
}

// MARK: - Preview

#Preview("Sample year") {
    let calendar = Calendar.current
    let year = Calendar.current.component(.year, from: Date())
    guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else {
        return Text("bad date")
    }

    var counts: [Date: Int] = [:]
    for i in 0 ..< 365 {
        if let d = calendar.date(byAdding: .day, value: i, to: start) {
            counts[calendar.startOfDay(for: d)] = Int.random(in: 0 ... 7)
        }
    }

    let weeks = CalendarService.generateYear(year, recordCounts: counts)

    return ScrollView {
        ContributionGridView(weeks: weeks, year: year)
            .padding()
    }
}
