import Foundation
import SwiftData

// MARK: - Calendar Service

/// Pure data types and service for the archive heatmap.
///
/// `CalendarService` owns no state — each call fetches a fresh snapshot
/// from the `ModelContext` and transforms it into display‑ready data.
///
/// ## DayInfo
///
/// One tile on the heatmap.  `count` determines the tile opacity.
///
/// ## WeekInfo
///
/// A column of 7 tiles (Mon‑Sun).  The first and last weeks of the year
/// may contain `nil` entries for padding when Jan 1 or Dec 31 falls
/// mid‑week.

// MARK: - CalendarDayInfo

struct CalendarDayInfo: Identifiable, Hashable {
    let date: Date
    let count: Int

    var id: String { "\(date.timeIntervalSince1970)" }
}

// MARK: - WeekInfo

struct WeekInfo: Identifiable {
    let id: Int
    let days: [CalendarDayInfo?]
}

// MARK: - CalendarService

enum CalendarService {

    /// Fetch all non‑trashed records in `year` and return a per‑day count map.
    /// - Parameter year: e.g. 2026
    /// - Parameter context: SwiftData context for the query
    /// - Returns: Dictionary keyed by `startOfDay`, value = number of records.
    static func queryRecordCounts(for year: Int, context: ModelContext) -> [Date: Int] {
        let calendar = Calendar.current

        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd   = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
        else { return [:] }

        let predicate = #Predicate<Record> { record in
            record.timestamp >= yearStart && record.timestamp < yearEnd && !record.isTrashed
        }

        let descriptor = FetchDescriptor<Record>(predicate: predicate)
        guard let records = try? context.fetch(descriptor) else { return [:] }

        var counts: [Date: Int] = [:]
        for record in records {
            let day = calendar.startOfDay(for: record.timestamp)
            counts[day, default: 0] += 1
        }
        return counts
    }

    // MARK: - Generate Year Grid

    /// Build the week‑column array for the contribution grid.
    ///
    /// The first week may have leading `nil` entries so that Jan 1 lands in
    /// the correct weekday column.  The last week is padded similarly.
    static func generateYear(_ year: Int, recordCounts: [Date: Int]) -> [WeekInfo] {
        let calendar = Calendar.current

        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        else { return [] }

        // Leading padding: how many empty cells before Jan 1.
        // weekday: 1=Sun, 2=Mon, …, 7=Sat  →  we want Mon=0.
        let weekday = calendar.component(.weekday, from: yearStart)
        let leadingPadding = (weekday - 2 + 7) % 7

        let daysInYear = calendar.range(of: .day, in: .year, for: yearStart)?.count ?? 365

        var weeks: [WeekInfo] = []
        var currentWeek: [CalendarDayInfo?] = []

        // Leading nils
        for _ in 0 ..< leadingPadding {
            currentWeek.append(nil)
        }

        // Fill real days
        for dayOffset in 0 ..< daysInYear {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: yearStart)
            else { continue }

            let startOfDay = calendar.startOfDay(for: date)
            let count = recordCounts[startOfDay] ?? 0
            currentWeek.append(CalendarDayInfo(date: date, count: count))

            if currentWeek.count == 7 {
                weeks.append(WeekInfo(id: weeks.count, days: currentWeek))
                currentWeek = []
            }
        }

        // Trailing nils
        if !currentWeek.isEmpty {
            while currentWeek.count < 7 {
                currentWeek.append(nil)
            }
            weeks.append(WeekInfo(id: weeks.count, days: currentWeek))
        }

        return weeks
    }

    // MARK: - Streak

    /// Consecutive days with at least one record, counting backward from
    /// the most recent day in `days`.
    static func currentStreak(days: [CalendarDayInfo]) -> Int {
        let sorted = days.sorted { $0.date > $1.date }
        var streak = 0
        for day in sorted {
            if day.count > 0 {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    /// Total records across the supplied day infos.
    static func totalRecordCount(days: [CalendarDayInfo]) -> Int {
        days.reduce(0) { $0 + $1.count }
    }
}
