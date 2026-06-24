import Foundation

// MARK: - Sync Status

/// Current state of the sync engine.
enum SyncStatus: Sendable {
    /// No sync in progress and no errors from the last attempt.
    case idle
    /// Actively uploading or downloading records.
    case syncing
    /// Last sync completed successfully.
    case success(Date)
    /// Last sync failed with an error.
    case failed(Error)

    var label: String {
        switch self {
        case .idle:        return "已就绪"
        case .syncing:     return "同步中…"
        case .success:     return "同步成功"
        case .failed:      return "同步失败"
        }
    }

    var isActive: Bool {
        if case .syncing = self { return true }
        return false
    }
}

// MARK: - Sync Service Protocol

/// Abstract sync contract.
/// Concrete implementations are injected via the environment.
protocol SyncService: AnyObject {
    /// Current sync status.
    var status: SyncStatus { get }

    /// Upload a single record to the remote store.
    func upload(record: Record) async throws

    /// Download all records from the remote store.
    func download() async throws -> [Record]

    /// Bidirectional sync between local and remote.
    func sync() async throws
}

// MARK: - Local (No-op) Implementation

/// Satisfies the protocol contract without performing any network I/O.
/// Used in Phase 1–3 where the app is fully offline‑first.
final class LocalSyncService: SyncService {
    private(set) var status: SyncStatus = .idle

    func upload(record: Record) async throws {
        // No-op
    }

    func download() async throws -> [Record] {
        // No-op
        return []
    }

    func sync() async throws {
        // No-op
    }
}

// MARK: - Cloud Sync (Placeholder)

/// Placeholder for the real iCloud sync implementation (Phase 5+).
///
/// This class exists to validate the architecture and will be replaced
/// with actual `CKContainer` / `NSUbiquitousKeyValueStore` code when
/// cloud sync is implemented.
///
/// ## Current behaviour
/// - `sync()` prints a diagnostic and always succeeds.
/// - `status` transitions to `.success` after a short delay.
final class CloudSyncService: SyncService {
    private(set) var status: SyncStatus = .idle

    func upload(record: Record) async throws {
        // Placeholder — will call CKRecord save in a future phase.
    }

    func download() async throws -> [Record] {
        // Placeholder — will return fetched CKRecords in a future phase.
        return []
    }

    func sync() async throws {
        await MainActor.run { status = .syncing }

        // Simulate network latency
        try await Task.sleep(nanoseconds: 1_000_000_000)

        await MainActor.run {
            status = .success(Date())
        }
    }
}
