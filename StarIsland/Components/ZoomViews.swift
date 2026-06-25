import SwiftUI

// MARK: - Week View

/// Weekly overview — one column per day of the current week.
///
/// Layout (7 columns):
/// ```
/// 23      24      25      26      27      28      29
/// 周一    周二    周三    周四    周五    周六    周日
/// 3条/5张 1条/0张 0条     2条/3张 4条/2张 1条/0张 0条
/// ```
struct WeekView: View {
    let records: [Record]
    let onTapDay: (Date) -> Void

    private let calendar = Calendar.current

    // MARK: - Body

    var body: some View {
        let weekDays = currentWeekDays

        ScrollView {
            VStack(spacing: 0) {
                // ── Week header ────────────────────────────────────
                weekHeader

                // ── Day columns ────────────────────────────────────
                LazyVStack(spacing: 0) {
                    ForEach(weekDays, id: \.self) { dayInfo in
                        WeekDayRow(
                            dayInfo: dayInfo,
                            isToday: calendar.isDateInToday(dayInfo.date)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onTapDay(dayInfo.date) }
                    }
                }
                .padding(.horizontal, AppTheme.spacing.xlarge)

                Spacer(minLength: AppTheme.spacing.huge)
            }
        }
    }

    // MARK: - Computed Data

    /// Days of the current week (Mon–Sun) with record/photo counts.
    private var currentWeekDays: [DayInfo] {
        let today = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))
        else { return [] }

        let recordsByDay = Dictionary(grouping: records) { record in
            calendar.startOfDay(for: record.timestamp)
        }

        return (0 ..< 7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            let dayRecords = recordsByDay[calendar.startOfDay(for: date)] ?? []
            return DayInfo(
                date: date,
                recordCount: dayRecords.count,
                photoCount: dayRecords.reduce(0) { $0 + $1.imagePaths.count }
            )
        }
    }

    // MARK: - Header

    private var weekHeader: some View {
        HStack(spacing: 0) {
            ForEach(currentWeekDays, id: \.self) { dayInfo in
                VStack(spacing: AppTheme.spacing.xxsmall) {
                    Text(dayLabel(dayInfo.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text("\(calendar.component(.day, from: dayInfo.date))")
                        .font(.subheadline)
                        .fontWeight(calendar.isDateInToday(dayInfo.date) ? .bold : .regular)
                        .foregroundStyle(calendar.isDateInToday(dayInfo.date) ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, AppTheme.spacing.xlarge)
        .padding(.vertical, AppTheme.spacing.medium)
    }

    // MARK: - Helpers

    private func dayLabel(_ date: Date) -> String {
        let weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        let idx = calendar.component(.weekday, from: date) - 2  // Mon = 0
        return idx >= 0 && idx < 7 ? weekdays[idx] : ""
    }
}

// MARK: - Week Day Row

private struct WeekDayRow: View {
    let dayInfo: DayInfo
    let isToday: Bool

    var body: some View {
        HStack(spacing: AppTheme.spacing.large) {
            // Date
            Text("\(Calendar.current.component(.day, from: dayInfo.date))")
                .font(.title3)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isToday ? Color.blue : .primary)
                .frame(width: 32, alignment: .leading)

            // Weekday
            Text(weekdayText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            // Visual bar
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius.small)
                    .fill(barColor)
                    .frame(width: max(4, geo.size.width * barWidthRatio), alignment: .leading)
            }
            .frame(height: 16)

            // Stats
            HStack(spacing: AppTheme.spacing.xxsmall) {
                if dayInfo.recordCount > 0 {
                    Text("\(dayInfo.recordCount)条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if dayInfo.photoCount > 0 {
                    Image(systemName: "photo")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(dayInfo.photoCount)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, AppTheme.spacing.small)
        .background(isToday ? Color.blue.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius.small))
    }

    private var weekdayText: String {
        let labels = ["一", "二", "三", "四", "五", "六", "日"]
        let idx = Calendar.current.component(.weekday, from: dayInfo.date) - 2
        return idx >= 0 && idx < 7 ? labels[idx] : ""
    }

    private var barColor: Color {
        dayInfo.recordCount == 0 ? .quaternary : Color.blue.opacity(barOpacity)
    }

    private var barWidthRatio: CGFloat {
        guard dayInfo.recordCount > 0 else { return 0.02 }
        return min(1.0, CGFloat(dayInfo.recordCount) / 10.0)
    }

    private var barOpacity: Double {
        switch dayInfo.recordCount {
        case 0:     return 0.3
        case 1:     return 0.35
        case 2, 3:  return 0.45
        case 4...6: return 0.6
        default:    return 0.75
        }
    }
}

// MARK: - Month View

/// Month calendar grid — heatmap cells by record count.
///
/// Layout (Apple Calendar style):
/// ```
///       六月 2026
///  日   一   二   三   四   五   六
///       1    2    3    4    5    6
///  7    8    9   10   11   12   13
///  ...
/// ```
/// Day cells use opacity based on record count.
struct MonthView: View {
    let records: [Record]
    let onTapDay: (Date) -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    // MARK: - Body

    var body: some View {
        let days = monthDays
        let today = calendar.startOfDay(for: Date())
        let recordsByDay = Dictionary(grouping: records) { record in
            calendar.startOfDay(for: record.timestamp)
        }

        ScrollView {
            VStack(spacing: 0) {
                // ── Month grid ─────────────────────────────────────
                monthGridHeader

                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(days.indices, id: \.self) { index in
                        if let date = days[index] {
                            let count = recordsByDay[calendar.startOfDay(for: date)]?.count ?? 0
                            MonthDayCell(
                                day: calendar.component(.day, from: date),
                                count: count,
                                isToday: calendar.isDateInToday(date),
                                isCurrentMonth: true
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onTapDay(date) }
                        } else {
                            Color.clear
                                .aspectRatio(1, contentMode: .fill)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.spacing.xlarge)
                .padding(.vertical, AppTheme.spacing.medium)

                // ── Stats summary ──────────────────────────────────
                monthStats

                Spacer(minLength: AppTheme.spacing.huge)
            }
        }
    }

    // MARK: - Computed Data

    private var monthDays: [Date?] {
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let monthRange = calendar.range(of: .day, in: .month, for: monthStart)
        else { return [] }

        // Leading padding (Sun = 0, Mon = 1, ..., Sat = 6)
        let weekday = calendar.component(.weekday, from: monthStart) - 1  // Sun = 0
        var cells: [Date?] = Array(repeating: nil, count: weekday)

        for day in monthRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                cells.append(date)
            }
        }

        return cells
    }

    // MARK: - Header

    private var monthGridHeader: some View {
        HStack(spacing: 0) {
            ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { label in
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, AppTheme.spacing.xlarge)
        .padding(.top, AppTheme.spacing.medium)
        .padding(.bottom, AppTheme.spacing.xsmall)
    }

    private var monthStats: some View {
        let days = monthDays.compactMap { $0 }
        let recordsByDay = Dictionary(grouping: records) { record in
            calendar.startOfDay(for: record.timestamp)
        }
        let dayCount = days.filter { (recordsByDay[calendar.startOfDay(for: $0)]?.count ?? 0) > 0 }.count
        let totalPhotos = records.reduce(0) { $0 + $1.imagePaths.count }

        return HStack(spacing: AppTheme.spacing.medium) {
            Text("\(records.count) 条记录")
            Text("·")
                .foregroundStyle(.tertiary)
            Text("\(dayCount) 天有记录")
            if totalPhotos > 0 {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(totalPhotos) 张照片")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, AppTheme.spacing.medium)
    }
}

// MARK: - Month Day Cell

private struct MonthDayCell: View {
    let day: Int
    let count: Int
    let isToday: Bool
    let isCurrentMonth: Bool

    var body: some View {
        ZStack {
            if count > 0 {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius.small)
                    .fill(Color.primary.opacity(heatmapOpacity))
                    .aspectRatio(1, contentMode: .fit)
                    .padding(2)
            }

            Text("\(day)")
                .font(.caption)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(foregroundColor)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(2)
    }

    private var foregroundColor: Color {
        if isToday { return .blue }
        return count > 0 ? .primary : .tertiary
    }

    private var heatmapOpacity: Double {
        switch count {
        case 0:     return 0
        case 1:     return 0.12
        case 2, 3:  return 0.20
        case 4...6: return 0.32
        default:    return 0.50
        }
    }
}

// MARK: - Shared Data Types

private struct DayInfo: Hashable {
    let date: Date
    let recordCount: Int
    let photoCount: Int
}

// MARK: - Preview

#Preview("WeekView") {
    WeekView(records: []) { _ in }
}

#Preview("MonthView") {
    MonthView(records: []) { _ in }
}
