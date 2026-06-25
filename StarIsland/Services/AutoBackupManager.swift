import Foundation
import SwiftData
import BackgroundTasks

// MARK: - Auto Backup Manager

/// Manages daily automatic backups in the background.
///
/// ## Behaviour
/// - On app launch, schedules a background task for the next midnight.
/// - If the app is in the foreground at midnight, the backup runs immediately.
/// - If a backup was already completed today, it is skipped.
/// - The backup writes to `Application Support/Backups/autobackup_YYYYMMdd.zip`.
/// - Old backups beyond the configured limit are automatically pruned.
final class AutoBackupManager {

    static let shared = AutoBackupManager()

    /// The `BGTaskScheduler` identifier registered in `Info.plist`.
    static let taskID = "com.starisland.autobackup"

    private init() {}

    // MARK: - Public API

    /// Call once at app launch (e.g. from `StarIslandApp.init()`).
    func setup() {
        // Register the background task handler
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskID,
                                         using: nil) { [weak self] task in
            self?.handleBackgroundTask(task as! BGProcessingTask)
        }

        // Also do a quick check: if auto‑backup is enabled and today's backup
        // hasn't been created yet, create it now (non‑blocking).
        if SettingsStorage.autoBackupEnabled {
            Task {
                await runBackupIfNeeded()
            }
        }

        // Schedule the first recurring task
        scheduleNext()
    }

    /// Schedule the next background backup (around midnight).
    func scheduleNext() {
        let request = BGProcessingTaskRequest(identifier: Self.taskID)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        // Schedule for next midnight + 5 minutes jitter
        let calendar = Calendar.current
        let now = Date()
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let nextMidnight = calendar.date(bySettingHour: 0, minute: 5, second: 0, of: tomorrow)
        else { return }

        request.earliestBeginDate = nextMidnight

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Silently fail — on‑launch check is the fallback
        }
    }

    // MARK: - Private

    private func handleBackgroundTask(_ task: BGProcessingTask) {
        guard SettingsStorage.autoBackupEnabled else {
            task.setTaskCompleted(success: true)
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            defer { semaphore.signal() }
            do {
                let container = try ModelContainer(for: Record.self)
                let context = await MainActor.run { container.mainContext }
                try await BackupService.performAutoBackup(context: context)
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }
        semaphore.wait()

        scheduleNext()
    }

    /// Check whether today's backup already exists; if not, run one.
    private func runBackupIfNeeded() async {
        guard SettingsStorage.autoBackupEnabled else { return }

        let today = DateFormatterManager.shared.dayTitle(from: Date())
            .replacingOccurrences(of: "年", with: "")
            .replacingOccurrences(of: "月", with: "")
            .replacingOccurrences(of: "日", with: "")
        let expectedName = "autobackup_\(today).zip"

        let existing = BackupService.existingBackups()
        if existing.contains(where: { $0.lastPathComponent == expectedName }) {
            return  // already backed up today
        }

        do {
            let container = try ModelContainer(for: Record.self)
            let context = await MainActor.run { container.mainContext }
            try await BackupService.performAutoBackup(context: context)
            scheduleNext()
        } catch {
            // Will retry on next launch or background task
        }
    }
}
