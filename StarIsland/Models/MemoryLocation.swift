import Foundation
import MapKit

// MARK: - Memory Location

/// An aggregated location derived from one or more records that share
/// the same `locationName`.
///
/// Instances are created by ``MapService/aggregateLocations(from:timeFilter:)``
/// and are never persisted directly — they are computed views over the
/// record store.
struct MemoryLocation: Identifiable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let recordCount: Int
    let firstDate: Date
    let latestDate: Date
    let records: [Record]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func == (lhs: MemoryLocation, rhs: MemoryLocation) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
