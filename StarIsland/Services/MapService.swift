import Foundation
import SwiftData
import MapKit

// MARK: - Time Filter

/// Segmented‑picker options for filtering the map pins.
enum TimeFilter: String, CaseIterable, Sendable {
    case today
    case week
    case month
    case all

    var label: String {
        switch self {
        case .today: return "今天"
        case .week:  return "最近7天"
        case .month: return "最近30天"
        case .all:   return "全部"
        }
    }

    /// Earliest date allowed by this filter (for `all` returns `nil`).
    var startDate: Date? {
        let now = Date()
        switch self {
        case .today:
            return Calendar.current.startOfDay(for: now)
        case .week:
            return Calendar.current.date(byAdding: .day, value: -7, to: now)
        case .month:
            return Calendar.current.date(byAdding: .day, value: -30, to: now)
        case .all:
            return nil
        }
    }

    /// Filter records in‑memory.  Keeps only records whose `timestamp` is
    /// on or after the filter's start date.
    func filter(_ records: [Record]) -> [Record] {
        guard let start = startDate else { return records }
        return records.filter { $0.timestamp >= start }
    }
}

// MARK: - Map Service

/// Stateless location aggregation and query helpers for the Memory Map.
enum MapService {

    // MARK: - Location Aggregation

    /// Group records by `locationName` and return one ``MemoryLocation``
    /// per group that has valid coordinates.
    ///
    /// - Coordinates are averaged across all records in the group.
    /// - Groups are sorted by `recordCount` descending.
    static func aggregateLocations(from records: [Record],
                                   timeFilter: TimeFilter) -> [MemoryLocation] {
        let filtered = timeFilter.filter(records)

        let grouped = Dictionary(grouping: filtered) { record in
            record.locationName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
        }

        return grouped.compactMap { key, group -> MemoryLocation? in
            guard !key.isEmpty,
                  let name = group.first?.locationName,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }

            // Average coordinates
            let validCoords = group.compactMap { r -> (lat: Double, lng: Double)? in
                guard let lat = r.latitude, let lng = r.longitude else { return nil }
                return (lat, lng)
            }
            guard !validCoords.isEmpty else { return nil }

            let avgLat = validCoords.reduce(0.0) { $0 + $1.lat } / Double(validCoords.count)
            let avgLng = validCoords.reduce(0.0) { $0 + $1.lng } / Double(validCoords.count)

            let dates = group.map(\.timestamp)
            let sortedRecords = group.sorted { $0.timestamp > $1.timestamp }

            return MemoryLocation(
                id: key,
                name: name,
                latitude: avgLat,
                longitude: avgLng,
                recordCount: group.count,
                firstDate: dates.min() ?? Date(),
                latestDate: dates.max() ?? Date(),
                records: sortedRecords
            )
        }
        .sorted { $0.recordCount > $1.recordCount }
    }

    // MARK: - Search

    /// Find the location whose name best matches `query`.
    static func searchLocation(_ query: String,
                               in locations: [MemoryLocation]) -> MemoryLocation? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Exact match first
        if let exact = locations.first(where: {
            $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) { return exact }

        // Contains match
        return locations.first { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Unique location names that contain `query`.
    static func matchingLocationNames(_ query: String,
                                       in locations: [MemoryLocation]) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return locations
            .filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            .map(\.name)
            .sorted()
    }

    // MARK: - Statistics

    static func totalLocations(_ locations: [MemoryLocation]) -> Int {
        locations.count
    }

    static func topLocation(_ locations: [MemoryLocation]) -> MemoryLocation? {
        locations.max(by: { $0.recordCount < $1.recordCount })
    }

    static func latestLocation(_ locations: [MemoryLocation]) -> MemoryLocation? {
        locations.max(by: { $0.latestDate < $1.latestDate })
    }

    /// Great‑circle distance in kilometres between the two locations
    /// farthest apart in the set.
    static func maxDistanceKm(_ locations: [MemoryLocation]) -> Double {
        guard locations.count >= 2 else { return 0 }

        var maxDist: Double = 0
        for i in 0 ..< locations.count {
            for j in (i + 1) ..< locations.count {
                let a = locations[i].coordinate
                let b = locations[j].coordinate
                let dist = distanceKm(from: a, to: b)
                maxDist = max(maxDist, dist)
            }
        }
        return maxDist
    }

    // MARK: - Footprint

    /// Chronologically ordered coordinates for records in the last 30 days
    /// that have valid lat/lng.
    static func footprintCoordinates(from records: [Record]) -> [CLLocationCoordinate2D] {
        guard let start = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else {
            return []
        }

        let recent = records
            .filter { $0.timestamp >= start && $0.latitude != nil && $0.longitude != nil }
            .sorted { $0.timestamp < $1.timestamp }

        return recent.map {
            CLLocationCoordinate2D(latitude: $0.latitude!, longitude: $0.longitude!)
        }
    }

    // MARK: - Helpers

    /// Haversine distance in km.
    private static func distanceKm(from a: CLLocationCoordinate2D,
                                   to b: CLLocationCoordinate2D) -> Double {
        let R = 6371.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let sinDLat = sin(dLat / 2)
        let sinDLon = sin(dLon / 2)
        let aVal = sinDLat * sinDLat + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sinDLon * sinDLon
        let c = 2 * atan2(sqrt(aVal), sqrt(1 - aVal))
        return R * c
    }
}
