import Foundation
import SwiftData

// MARK: - Record

/// A single time-slice record — evidence of a moment.
///
/// # Migration Notes
/// - **Phase 2** (`mood: String?` → `Mood?`): breaking — reinstall required.
/// - **Phase 2.5** (`isTrashed` / `trashedAt`): additive only, safe to deploy
///   alongside existing stores.  Default values (`false` / `nil`) are filled in
///   by SwiftData for rows written by older versions.
@Model
final class Record {
    // MARK: - Phase 1

    var id: UUID
    var timestamp: Date
    var text: String

    // MARK: - Phase 2

    var mood: Mood?

    // MARK: - Phase 1.5

    var locationName: String?
    var createdAt: Date
    var updatedAt: Date
    var imagePaths: [String]
    var latitude: Double?
    var longitude: Double?
    var weather: String?
    var tags: [String]

    // MARK: - Phase 2.5 (Soft Delete)

    /// `true` when the user has "deleted" the record.
    /// Trashed records are hidden from the timeline but preserved in the store
    /// for a future trash / recovery feature.
    var isTrashed: Bool = false

    /// The moment the record was trashed, or `nil` if still active.
    var trashedAt: Date?

    // MARK: - Phase 4.8 (Voice Notes)

    /// Filenames of recorded audio clips (`.m4a`) stored via ``AudioStorageService``.
    /// Multiple recordings are supported per record.
    var audioPaths: [String] = []

    // MARK: - Phase 4 (Sync)

    /// Stable identifier used for deduplication during cross‑device sync and
    /// backup import.  Unlike `id` (which is local‑first), `syncId` is
    /// designed to be stable across devices.
    ///
    /// Existing records get `nil` until the first sync operation assigns one.
    var syncId: UUID?

    /// Monotonically increasing version counter for conflict resolution.
    /// Starts at 1 for new records and increments on every local edit.
    var syncVersion: Int = 1

    // MARK: - Init

    init(
        text: String,
        mood: Mood? = nil,
        locationName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        weather: String? = nil,
        tags: [String] = [],
        imagePaths: [String] = [],
        audioPaths: [String] = []
    ) {
        let now = Date()

        self.id = UUID()
        self.timestamp = now
        self.text = text
        self.mood = mood
        self.locationName = locationName

        self.createdAt = now
        self.updatedAt = now
        self.imagePaths = imagePaths
        self.audioPaths = audioPaths
        self.latitude = latitude
        self.longitude = longitude
        self.weather = weather
        self.tags = tags

        self.isTrashed = false
        self.trashedAt = nil

        self.syncId = nil
        self.syncVersion = 1
    }
}
