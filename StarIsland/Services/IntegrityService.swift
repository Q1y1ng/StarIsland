import Foundation
import SwiftData

// MARK: - Database Health

/// Snapshot of database and filesystem integrity.
struct DatabaseHealth: Sendable {
    /// Total record count (including trashed)
    let totalRecords: Int
    /// Records whose referenced image files are missing from disk
    let recordsWithMissingImages: Int
    /// Records whose referenced audio files are missing from disk
    let recordsWithMissingAudio: Int
    /// Image files on disk that no record references
    let orphanedImages: Int
    /// Audio files on disk that no record references
    let orphanedAudio: Int
    /// Records sharing the same `syncId` (always 0 after auto‑repair)
    let duplicateSyncIds: Int
    /// Estimated database file size in bytes
    let databaseSizeBytes: Int64
    /// Total size of all image files in bytes
    let imagesSizeBytes: Int64
    /// Total size of all audio files in bytes
    let audioSizeBytes: Int64

    var isHealthy: Bool {
        recordsWithMissingImages == 0 && orphanedImages == 0
        && recordsWithMissingAudio == 0 && orphanedAudio == 0
        && duplicateSyncIds == 0
    }
}

// MARK: - Integrity Service

/// Background data integrity checks and automatic repair.
///
/// All methods are `@MainActor` because `ModelContext` is not `Sendable`.
/// Called once at app launch via ``IntegrityService.runAll(context:)``.
@MainActor
enum IntegrityService {

    /// Run every health check and auto‑repair **sequentially**.
    ///
    /// Must run on `@MainActor` — ``ModelContext`` is not `Sendable`, so
    /// concurrent access (e.g. via ``withTaskGroup``) produces
    /// `EXC_BAD_ACCESS` as multiple child tasks read the same context
    /// while ``fixDuplicateSyncIds(context:)`` deletes records.
    /// - Parameter context: A `ModelContext` created on the MainActor.
    static func runAll(context: ModelContext) async {
        await checkOrphanedImages(context: context)
        await checkOrphanedAudio(context: context)
        await checkMissingImages(context: context)
        await checkMissingAudio(context: context)
        await fixDuplicateSyncIds(context: context)
    }

    /// Compute a health snapshot (read‑only, no repair).
    /// - Parameter context: A `ModelContext` (must be on `@MainActor`).
    /// - Returns: A ``DatabaseHealth`` struct.
    static func computeHealth(context: ModelContext) async -> DatabaseHealth {
        let records = (try? context.fetch(FetchDescriptor<Record>())) ?? []

        // ── Missing images ──────────────────────────────────────────
        let fm = FileManager.default
        var missingImageCount = 0
        for record in records {
            for path in record.imagePaths {
                let url = ImageStorageService.url(for: path)
                if !fm.fileExists(atPath: url.path) { missingImageCount += 1 }
            }
        }

        // ── Missing audio ───────────────────────────────────────────
        var missingAudioCount = 0
        for record in records {
            for path in record.audioPaths {
                let url = AudioStorageService.url(for: path)
                if !fm.fileExists(atPath: url.path) { missingAudioCount += 1 }
            }
        }

        // ── Orphaned images ─────────────────────────────────────────
        let referencedImages = Set(records.flatMap(\.imagePaths))
        let imagesDir = ImageStorageService.imagesDir
        var orphanedImageCount = 0
        if let files = try? fm.contentsOfDirectory(atPath: imagesDir.path) {
            for file in files where !referencedImages.contains(file) {
                orphanedImageCount += 1
            }
        }

        // ── Orphaned audio ──────────────────────────────────────────
        let referencedAudio = Set(records.flatMap(\.audioPaths))
        let audioDir = AudioStorageService.audioDir
        var orphanedAudioCount = 0
        if let files = try? fm.contentsOfDirectory(atPath: audioDir.path) {
            for file in files where !referencedAudio.contains(file) {
                orphanedAudioCount += 1
            }
        }

        // ── Duplicate syncIds ───────────────────────────────────────
        let syncIds = records.compactMap(\.syncId)
        let dupCount = syncIds.count - Set(syncIds).count

        // ── File sizes ──────────────────────────────────────────────
        let dbSize = databaseFileSize()
        let imagesSize = directorySize(imagesDir)
        let audioSize = directorySize(audioDir)

        return DatabaseHealth(
            totalRecords: records.count,
            recordsWithMissingImages: missingImageCount,
            recordsWithMissingAudio: missingAudioCount,
            orphanedImages: orphanedImageCount,
            orphanedAudio: orphanedAudioCount,
            duplicateSyncIds: dupCount,
            databaseSizeBytes: dbSize,
            imagesSizeBytes: imagesSize,
            audioSizeBytes: audioSize
        )
    }

    // MARK: - Individual Checks

    /// Delete image files that are no longer referenced by any record.
    private static func checkOrphanedImages(context: ModelContext) async {
        let records = (try? context.fetch(FetchDescriptor<Record>())) ?? []
        let referenced = Set(records.flatMap(\.imagePaths))

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: ImageStorageService.imagesDir.path)
        else { return }

        for file in files where !referenced.contains(file) {
            try? fm.removeItem(at: ImageStorageService.url(for: file))
        }
    }

    /// Delete audio files that are no longer referenced by any record.
    private static func checkOrphanedAudio(context: ModelContext) async {
        let records = (try? context.fetch(FetchDescriptor<Record>())) ?? []
        let referenced = Set(records.flatMap(\.audioPaths))

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: AudioStorageService.audioDir.path)
        else { return }

        for file in files where !referenced.contains(file) {
            try? fm.removeItem(at: AudioStorageService.url(for: file))
        }
    }

    /// Mark records whose referenced images are missing.
    private static func checkMissingImages(context: ModelContext) async {
        let records = (try? context.fetch(FetchDescriptor<Record>())) ?? []
        let fm = FileManager.default

        for record in records {
            let hasMissing = record.imagePaths.contains { path in
                !fm.fileExists(atPath: ImageStorageService.url(for: path).path)
            }
            if hasMissing {
                // Mark is not persisted in model — we just count it in health.
                // Future: add `hasMissingImages` field if needed.
            }
        }
    }

    /// Mark records whose referenced audio files are missing.
    private static func checkMissingAudio(context: ModelContext) async {
        let records = (try? context.fetch(FetchDescriptor<Record>())) ?? []
        let fm = FileManager.default

        for record in records {
            let hasMissing = record.audioPaths.contains { path in
                !fm.fileExists(atPath: AudioStorageService.url(for: path).path)
            }
            if hasMissing {
                // Counted in health snapshot — no auto‑repair needed.
            }
        }
    }

    /// Merge records that share the same `syncId` by keeping the one with
    /// the higher `syncVersion` and deleting duplicates.
    private static func fixDuplicateSyncIds(context: ModelContext) async {
        let records = (try? context.fetch(FetchDescriptor<Record>())) ?? []

        // Only records with a non‑nil syncId
        let withSyncId = records.compactMap { r -> (UUID, Record)? in
            guard let sid = r.syncId else { return nil }
            return (sid, r)
        }

        var byId: [UUID: [Record]] = [:]
        for (sid, rec) in withSyncId {
            byId[sid, default: []].append(rec)
        }

        for (_, group) in byId where group.count > 1 {
            let sorted = group.sorted { $0.syncVersion > $1.syncVersion }
            // Keep the highest version, delete the rest
            for record in sorted.dropFirst() {
                context.delete(record)
            }
        }

        try? context.save()
    }

    // MARK: - Helpers

    private static func databaseFileSize() -> Int64 {
        let fm = FileManager.default
        let supportDir = fm.urls(for: .applicationSupportDirectory,
                                  in: .userDomainMask).first!
        guard let contents = try? fm.contentsOfDirectory(
            at: supportDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        let total = contents.filter { $0.pathExtension == "sqlite" || $0.pathExtension == "store" }
            .reduce(Int64(0)) { sum, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return sum + Int64(size)
            }
        return total
    }

    private static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}

// MARK: - Preview Helpers

extension DatabaseHealth {
    static let zero = DatabaseHealth(
        totalRecords: 0,
        recordsWithMissingImages: 0,
        recordsWithMissingAudio: 0,
        orphanedImages: 0,
        orphanedAudio: 0,
        duplicateSyncIds: 0,
        databaseSizeBytes: 0,
        imagesSizeBytes: 0,
        audioSizeBytes: 0
    )
}
