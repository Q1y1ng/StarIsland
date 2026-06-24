import Foundation
import SwiftData
import UIKit

// MARK: - Backup Service

/// Export and import the entire StarIsland record store as a ZIP archive.
///
/// ```
/// StarIslandBackup_20260624.zip
/// ├── metadata.json        ← BackupMetadata
/// ├── records.json         ← [BackupRecord]
/// └── images/              ← all referenced image files
/// ```
///
/// ## Deduplication
/// Import uses `syncId` to detect duplicates.  A record with the same `syncId`
/// as an existing one is skipped — the local copy is considered authoritative.
///
/// ## Thread safety
/// All methods are `async` and perform file I/O on a background thread.
enum BackupService {

    /// Directory where auto‑backups are stored.
    static let backupsDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                  withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Export

    /// Build a backup archive and return its file URL.
    ///
    /// - Parameter context: A `ModelContext` to fetch records from.
    /// - Returns: The URL of the generated `.zip` file in a temporary directory.
    static func exportBackup(context: ModelContext) async throws -> URL {
        let descriptor = FetchDescriptor<Record>()
        let records = try context.fetch(descriptor)

        let backupRecords = records.map { $0.toBackupRecord() }
        let imageCount = records.reduce(0) { $0 + $1.imagePaths.count }

        let metadata = BackupMetadata(
            appVersion: appVersion,
            exportDate: Date(),
            recordCount: records.count,
            photoCount: imageCount,
            schemaVersion: 1
        )

        // Build in a temp directory
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir,
                                                 withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // metadata.json
        let metaData = try JSONEncoder.ISO8601.encode(metadata)
        try metaData.write(to: tmpDir.appendingPathComponent("metadata.json"),
                           options: .atomic)

        // records.json
        let recordsData = try JSONEncoder.ISO8601.encode(backupRecords)
        try recordsData.write(to: tmpDir.appendingPathComponent("records.json"),
                              options: .atomic)

        // images/
        let imagesDir = tmpDir.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir,
                                                 withIntermediateDirectories: true)

        for record in records {
            for filename in record.imagePaths {
                let src = ImageStorageService.url(for: filename)
                let dst = imagesDir.appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: src.path) {
                    try FileManager.default.copyItem(at: src, to: dst)
                }
            }
        }

        // Create zip
        let dateStr = DateFormatterManager.shared.fullDateTime(from: Date())
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let zipName = "StarIslandBackup_\(dateStr).zip"
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(zipName)

        // Remove any previous file with the same name
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }

        try ZipHelper.createZip(from: tmpDir, to: zipURL)
        return zipURL
    }

    // MARK: - Import

    /// Import a backup archive, deduplicating by `syncId`.
    ///
    /// - Parameters:
    ///   - zipURL: The ZIP file URL.
    ///   - context: A `ModelContext` to insert records into.
    /// - Returns: An ``ImportResult`` describing what was added.
    @discardableResult
    static func importBackup(from zipURL: URL, context: ModelContext) async throws -> ImportResult {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir,
                                                 withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Extract
        try ZipHelper.extractZip(from: zipURL, to: tmpDir)

        // Parse metadata
        let metaURL = tmpDir.appendingPathComponent("metadata.json")
        guard FileManager.default.fileExists(atPath: metaURL.path) else {
            throw BackupError.missingMetadata
        }
        let metaData = try Data(contentsOf: metaURL)
        let metadata = try JSONDecoder.ISO8601.decode(BackupMetadata.self, from: metaData)

        guard metadata.schemaVersion == 1 else {
            throw BackupError.unsupportedSchema(metadata.schemaVersion)
        }

        // Parse records
        let recordsURL = tmpDir.appendingPathComponent("records.json")
        guard FileManager.default.fileExists(atPath: recordsURL.path) else {
            throw BackupError.missingRecords
        }
        let recordsData = try Data(contentsOf: recordsURL)
        let backupRecords = try JSONDecoder.ISO8601.decode([BackupRecord].self, from: recordsData)

        // Build set of existing syncIds
        let existingDescriptor = FetchDescriptor<Record>()
        let existingRecords = try context.fetch(existingDescriptor)
        let existingSyncIds = Set(existingRecords.compactMap { $0.syncId?.uuidString.lowercased() })

        // Images directory
        let imagesDir = tmpDir.appendingPathComponent("images", isDirectory: true)

        var newCount = 0
        var skipCount = 0
        var photoCount = 0

        for backupRecord in backupRecords {
            let syncIdLower = backupRecord.syncId.lowercased()

            if existingSyncIds.contains(syncIdLower) {
                skipCount += 1
                continue
            }

            // Copy images
            var newImagePaths: [String] = []
            for filename in backupRecord.imageFilenames {
                let src = imagesDir.appendingPathComponent(filename)
                guard FileManager.default.fileExists(atPath: src.path) else { continue }
                // Use ImageStorageService to save with a new unique filename
                let data = try Data(contentsOf: src)
                if let savedName = ImageStorageService.save(data) {
                    newImagePaths.append(savedName)
                    photoCount += 1
                }
            }

            // Create Record
            let record = Record(
                text: backupRecord.text,
                mood: Mood(rawValue: backupRecord.mood ?? ""),
                locationName: backupRecord.locationName,
                latitude: backupRecord.latitude,
                longitude: backupRecord.longitude,
                weather: backupRecord.weather,
                tags: backupRecord.tags,
                imagePaths: newImagePaths
            )

            // Restore original metadata
            record.id = UUID(uuidString: backupRecord.syncId) ?? record.id
            record.syncId = UUID(uuidString: backupRecord.syncId)
            record.syncVersion = backupRecord.syncVersion
            record.timestamp = backupRecord.timestamp
            record.createdAt = backupRecord.createdAt
            record.updatedAt = backupRecord.updatedAt
            record.isTrashed = backupRecord.isTrashed
            record.trashedAt = backupRecord.trashedAt

            context.insert(record)
            newCount += 1
        }

        try context.save()

        return ImportResult(
            newRecords: newCount,
            skippedRecords: skipCount,
            newPhotos: photoCount
        )
    }

    // MARK: - Auto‑backup management

    /// Return all auto‑backup ZIP files sorted newest first.
    static func existingBackups() -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: backupsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .filter { $0.pathExtension.lowercased() == "zip" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
    }

    /// Remove backups beyond the configured limit.
    static func cleanOldBackups(limit: Int) {
        let backups = existingBackups()
        guard backups.count > limit else { return }

        let toDelete = backups[limit...]
        for url in toDelete {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Perform an auto‑backup now (called by ``AutoBackupManager``).
    @discardableResult
    static func performAutoBackup(context: ModelContext) async throws -> URL {
        let zipURL = try await exportBackup(context: context)

        // Move to backups directory with a clean name
        let dateStr = DateFormatterManager.shared.dayTitle(from: Date())
            .replacingOccurrences(of: "年", with: "")
            .replacingOccurrences(of: "月", with: "")
            .replacingOccurrences(of: "日", with: "")
        let dstName = "autobackup_\(dateStr).zip"
        let dstURL = backupsDir.appendingPathComponent(dstName)

        if FileManager.default.fileExists(atPath: dstURL.path) {
            try FileManager.default.removeItem(at: dstURL)
        }
        try FileManager.default.moveItem(at: zipURL, to: dstURL)

        // Enforce retention limit
        let limit = max(SettingsStorage.backupLimit, 1)
        cleanOldBackups(limit: limit)

        return dstURL
    }

    // MARK: - Helpers

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Errors

enum BackupError: LocalizedError {
    case missingMetadata
    case missingRecords
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .missingMetadata:
            return "备份文件缺少 metadata.json"
        case .missingRecords:
            return "备份文件缺少 records.json"
        case .unsupportedSchema(let v):
            return "不支持的备份版本: \(v)"
        }
    }
}

// MARK: - Encoder / Decoder extensions

private extension JSONEncoder {
    static let ISO8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

private extension JSONDecoder {
    static let ISO8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - Record → BackupRecord

private extension Record {
    func toBackupRecord() -> BackupRecord {
        BackupRecord(
            syncId: syncId?.uuidString.lowercased() ?? id.uuidString.lowercased(),
            syncVersion: syncVersion,
            timestamp: timestamp,
            text: text,
            mood: mood?.rawValue,
            locationName: locationName,
            createdAt: createdAt,
            updatedAt: updatedAt,
            imageFilenames: imagePaths,
            latitude: latitude,
            longitude: longitude,
            weather: weather,
            tags: tags,
            isTrashed: isTrashed,
            trashedAt: trashedAt
        )
    }
}
