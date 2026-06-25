import SwiftUI

// MARK: - Home Header View

/// Large-formatted date header shown at the top of the timeline.
///
/// Adapts its content based on the current zoom level — day, week, month, or year.
///
/// ## Day mode (Apple Journal style)
/// ```
/// 今天
/// 2026年06月25日 星期三
/// 已记录: 第 17 天 · 83 条记录
/// ```
struct HomeHeaderView: View {
    let recordCount: Int
    var firstRecordDate: Date? = nil
    var zoomLevel: TimelineZoomLevel = .day
    var statsLine: String? = nil          /// overrides default stats text
    var subtitleOverride: String? = nil   /// overrides default subtitle

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xsmall) {
            Text(headerTitle)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            HStack(spacing: AppTheme.spacing.medium) {
                Text(resolvedSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if zoomLevel == .day {
                    Text(Date().weekday)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(resolvedStats)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, AppTheme.spacing.xxxsmall)

            if zoomLevel == .day {
                Text("HEAOZIE")
                    .font(.caption2)
                    .foregroundStyle(.quaternary.opacity(0.5))
                    .padding(.top, AppTheme.spacing.xxxsmall)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.spacing.xlarge)
        .padding(.top, AppTheme.spacing.xlarge)
        .padding(.bottom, AppTheme.spacing.medium)
    }

    // MARK: - Zoom‑Aware Content

    private var headerTitle: String {
        switch zoomLevel {
        case .day:   return "今天"
        case .week:  return "本周"
        case .month: return monthYearTitle
        case .year:  return "\(calendar.component(.year, from: Date()))"
        }
    }

    private var resolvedSubtitle: String {
        subtitleOverride ?? defaultSubtitle
    }

    private var resolvedStats: String {
        statsLine ?? defaultStats
    }

    private var defaultSubtitle: String {
        switch zoomLevel {
        case .day:   return Date().dayTitle
        case .week:  return weekDateRange
        case .month: return "\(recordCount) 条记录"
        case .year:  return "共 \(recordCount) 条记录"
        }
    }

    private var defaultStats: String {
        switch zoomLevel {
        case .day:
            if recordCount == 0 { return "暂无记录" }
            guard let first = firstRecordDate else { return "共 \(recordCount) 条记录" }
            let days = calendar.dateComponents([.day], from: first, to: Date()).day ?? 0
            return "已记录: 第 \(days + 1) 天 · 共 \(recordCount) 条记录"
        case .week, .month, .year:
            return ""
        }
    }

    // MARK: - Helpers

    private var monthYearTitle: String {
        let now = Date()
        let y = calendar.component(.year, from: now)
        let m = calendar.component(.month, from: now)
        return "\(y)年\(m)月"
    }

    private var weekDateRange: String {
        let today = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)),
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)
        else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "MM/dd"
        return "\(fmt.string(from: weekStart)) — \(fmt.string(from: weekEnd))"
    }
}

// MARK: - Preview

#Preview("Day") {
    HomeHeaderView(recordCount: 83, firstRecordDate: Date().addingTimeInterval(-86400 * 16), zoomLevel: .day)
}

#Preview("Week") {
    HomeHeaderView(recordCount: 12, zoomLevel: .week)
}
