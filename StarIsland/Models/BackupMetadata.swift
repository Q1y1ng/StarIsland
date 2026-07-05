import Foundation

// MARK: - Backup Metadata

/// Metadata stored in every backup archive as `metadata.json`.
///
/// This file is the first thing read during import, providing version
/// information before any record data is touched.  The `schemaVersion`
/// field allows forward‑compatible migrations years from now.
struct BackupMetadata: Codable {
    let appVersion: String
    let exportDate: Date
    let recordCount: Int
    let photoCount: Int
    let schemaVersion: Int
}

// MARK: - Backup Record (JSON representation)

/// Archivable representation of a ``Record``, independent of SwiftData.
///
/// Exported as `records.json`.  The `syncId` field is the deduplication
/// key during import — if a record with the same `syncId` already exists
/// in the local store, the import skips it.
struct BackupRecord: Codable {
    let syncId: String
    let syncVersion: Int
    let timestamp: Date
    let text: String
    let mood: String?
    let locationName: String?
    let createdAt: Date
    let updatedAt: Date
    let imageFilenames: [String]
    let audioFilenames: [String]
    let latitude: Double?
    let longitude: Double?
    let weather: String?
    let tags: [String]
    let isTrashed: Bool
    let trashedAt: Date?

    // MARK: - Init

    init(
        syncId: String,
        syncVersion: Int,
        timestamp: Date,
        text: String,
        mood: String?,
        locationName: String?,
        createdAt: Date,
        updatedAt: Date,
        imageFilenames: [String],
        audioFilenames: [String],
        latitude: Double?,
        longitude: Double?,
        weather: String?,
        tags: [String],
        isTrashed: Bool,
        trashedAt: Date?
    ) {
        self.syncId = syncId
        self.syncVersion = syncVersion
        self.timestamp = timestamp
        self.text = text
        self.mood = mood
        self.locationName = locationName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.imageFilenames = imageFilenames
        self.audioFilenames = audioFilenames
        self.latitude = latitude
        self.longitude = longitude
        self.weather = weather
        self.tags = tags
        self.isTrashed = isTrashed
        self.trashedAt = trashedAt
    }

    // MARK: - Codable (backward‑compatible with old backups without audioFilenames)

    enum CodingKeys: String, CodingKey {
        case syncId, syncVersion, timestamp, text, mood, locationName
        case createdAt, updatedAt, imageFilenames, audioFilenames
        case latitude, longitude, weather, tags, isTrashed, trashedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        syncId = try container.decode(String.self, forKey: .syncId)
        syncVersion = try container.decode(Int.self, forKey: .syncVersion)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        text = try container.decode(String.self, forKey: .text)
        mood = try container.decodeIfPresent(String.self, forKey: .mood)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        imageFilenames = try container.decode([String].self, forKey: .imageFilenames)
        audioFilenames = try container.decodeIfPresent([String].self, forKey: .audioFilenames) ?? []
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        weather = try container.decodeIfPresent(String.self, forKey: .weather)
        tags = try container.decode([String].self, forKey: .tags)
        isTrashed = try container.decode(Bool.self, forKey: .isTrashed)
        trashedAt = try container.decodeIfPresent(Date.self, forKey: .trashedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(syncId, forKey: .syncId)
        try container.encode(syncVersion, forKey: .syncVersion)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(mood, forKey: .mood)
        try container.encodeIfPresent(locationName, forKey: .locationName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(imageFilenames, forKey: .imageFilenames)
        try container.encode(audioFilenames, forKey: .audioFilenames)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(weather, forKey: .weather)
        try container.encode(tags, forKey: .tags)
        try container.encode(isTrashed, forKey: .isTrashed)
        try container.encodeIfPresent(trashedAt, forKey: .trashedAt)
    }
}

// MARK: - Manifest

/// The parsed contents of an imported backup archive.
struct BackupManifest {
    let metadata: BackupMetadata
    let records: [BackupRecord]

    var recordCount: Int { records.count }
    var photoCount: Int { records.reduce(0) { $0 + $1.imageFilenames.count } }
}

// MARK: - Import Result

/// Summary shown to the user after a successful import.
struct ImportResult: CustomStringConvertible {
    let newRecords: Int
    let skippedRecords: Int
    let newPhotos: Int

    var description: String {
        "新增 \(newRecords) 条记录，\(newPhotos) 张照片" +
        (skippedRecords > 0 ? "，跳过 \(skippedRecords) 条重复" : "")
    }
}
