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
    let latitude: Double?
    let longitude: Double?
    let weather: String?
    let tags: [String]
    let isTrashed: Bool
    let trashedAt: Date?
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
