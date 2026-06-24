import Foundation
import SwiftData

// MARK: - App Stats

/// Immutable snapshot of computed statistics.
struct AppStats: Equatable {
    let recordCount: Int
    let photoCount: Int
    let longestStreak: Int
    let firstRecordDate: Date?
    let latestRecordDate: Date?
    let topLocation: String?
    let topMood: Mood?
    let averagePerDay: Double

    // MARK: Phase 3.5 — Location stats

    /// Number of unique named locations across all records.
    let totalLocations: Int
    /// Great‑circle distance in km between the two farthest locations.
    let farthestDistanceKm: Double
    /// Name of the most recently visited location.
    let latestLocation: String?

    static let zero = AppStats(
        recordCount: 0,
        photoCount: 0,
        longestStreak: 0,
        firstRecordDate: nil,
        latestRecordDate: nil,
        topLocation: nil,
        topMood: nil,
        averagePerDay: 0,
        totalLocations: 0,
        farthestDistanceKm: 0,
        latestLocation: nil
    )
}

// MARK: - Stats Service

/// Stateless computations over the full record store.
///
/// Every method fetches a fresh snapshot — callers are responsible for
/// caching the result if it needs to survive across view updates.
enum StatsService {

    /// Gather all stats from the current store.
    static func compute(context: ModelContext) -> AppStats {
        let descriptor = FetchDescriptor<Record>(
            predicate: #Predicate { !$0.isTrashed }
        )
        guard let records = try? context.fetch(descriptor) else { return .zero }

        return compute(from: records)
    }

    /// Compute stats from an already‑fetched array (avoids a second fetch
    /// when the caller already has records in memory).
    static func compute(from records: [Record]) -> AppStats {
        let recordCount = records.count
        let photoCount = records.reduce(0) { $0 + $1.imagePaths.count }

        let sorted = records.sorted { $0.timestamp < $1.timestamp }
        let firstDate = sorted.first?.timestamp
        let latestDate = sorted.last?.timestamp

        // Top location
        let locationCounts = Dictionary(
            grouping: records.compactMap(\.locationName).filter { !$0.isEmpty }
        ) { $0 }.mapValues(\.count)
        let topLocation = locationCounts.max { $0.value < $1.value }?.key

        // Top mood
        let moodCounts = Dictionary(
            grouping: records.compactMap(\.mood)
        ) { $0 }.mapValues(\.count)
        let topMood = moodCounts.max { $0.value < $1.value }?.key

        // Average per day
        let averagePerDay: Double = {
            guard let first = firstDate, let last = latestDate else { return 0 }
            let days = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: first),
                to: Calendar.current.startOfDay(for: last)
            ).day ?? 0
            return days >= 0 ? Double(recordCount) / max(Double(days + 1), 1) : 0
        }()

        // Longest streak
        let longestStreak: Int = {
            let daySet = Set(records.map { Calendar.current.startOfDay(for: $0.timestamp) })
            let daySorted = daySet.sorted()
            var best = 0, current = 0
            var previous: Date?
            for day in daySorted {
                if let prev = previous,
                   Calendar.current.dateComponents([.day], from: prev, to: day).day == 1 {
                    current += 1
                } else {
                    current = 1
                }
                best = max(best, current)
                previous = day
            }
            return best
        }()

        // ---- Phase 3.5: Location stats ----

        // Unique named locations
        let uniqueNames = Set(
            records.compactMap(\.locationName).filter { !$0.isEmpty }
        )
        let totalLocations = uniqueNames.count

        // Farthest distance via MapService
        let locations = MapService.aggregateLocations(
            from: records,
            timeFilter: .all
        )
        let farthestDistanceKm = MapService.maxDistanceKm(locations)

        // Latest location
        let latestLocation = sorted
            .compactMap { r -> (name: String, date: Date)? in
                guard let name = r.locationName, !name.isEmpty else { return nil }
                return (name, r.timestamp)
            }
            .max(by: { $0.date < $1.date })?
            .name

        return AppStats(
            recordCount: recordCount,
            photoCount: photoCount,
            longestStreak: longestStreak,
            firstRecordDate: firstDate,
            latestRecordDate: latestDate,
            topLocation: topLocation,
            topMood: topMood,
            averagePerDay: averagePerDay,
            totalLocations: totalLocations,
            farthestDistanceKm: farthestDistanceKm,
            latestLocation: latestLocation
        )
    }
}
