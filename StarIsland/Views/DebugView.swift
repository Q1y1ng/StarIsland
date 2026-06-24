import SwiftUI
import SwiftData
import MachO

// MARK: - Debug View

/// Developer diagnostics — only compiled in `DEBUG` configuration.
///
/// Shows internal metrics that are useful during development but should
/// never appear in release builds.  The entire view is hidden behind
/// `#if DEBUG`.
///
/// ## Metrics
/// - Record / photo / cache counts
/// - Database and image file sizes
/// - App version and build
/// - Approximate memory footprint
/// - Launch timestamp
#if DEBUG
struct DebugView: View {
    @Environment(\.modelContext) private var context

    @State private var recordCount = 0
    @State private var trashedCount = 0
    @State private var photoCount = 0
    @State private var imageCacheCount = 0
    @State private var databaseSize: Int64 = 0
    @State private var imagesSize: Int64 = 0
    @State private var backupCount = 0
    @State private var memoryString = ""
    @State private var launchTime: Date = .init()
    @State private var health: DatabaseHealth = .zero

    private let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    private let startTime = Date()

    var body: some View {
        Form {
            // ── Summary ─────────────────────────────────────────────
            Section("StarIsland") {
                StatRow(icon: "tag",
                        label: "Version",
                        value: appVersion)
                StatRow(icon: "number",
                        label: "Build",
                        value: buildNumber)
                StatRow(icon: "clock",
                        label: "启动时间",
                        value: DateFormatterManager.shared
                            .fullDateTime(from: startTime))
            }

            // ── Records ─────────────────────────────────────────────
            Section("数据") {
                StatRow(icon: "doc.text",
                        label: "记录数",
                        value: "\(recordCount)")
                StatRow(icon: "trash",
                        label: "回收站",
                        value: "\(trashedCount)")
                StatRow(icon: "photo",
                        label: "照片数",
                        value: "\(photoCount)")
                StatRow(icon: "photo.on.rectangle.angled",
                        label: "图片缓存",
                        value: "\(imageCacheCount)")
            }

            // ── Storage ─────────────────────────────────────────────
            Section("存储") {
                StatRow(icon: "internaldrive",
                        label: "数据库",
                        value: byteFormatter.string(fromByteCount: databaseSize))
                StatRow(icon: "photo.on.rectangle.angled",
                        label: "图片文件",
                        value: byteFormatter.string(fromByteCount: imagesSize))
            }

            // ── Performance ─────────────────────────────────────────
            Section("性能") {
                StatRow(icon: "memorychip",
                        label: "内存 (近似)",
                        value: memoryString)
                StatRow(icon: "archivebox",
                        label: "备份数",
                        value: "\(backupCount)")
            }

            // ── Health ──────────────────────────────────────────────
            Section("健康") {
                HStack {
                    StatRow(icon: "heart",
                            label: "状态",
                            value: health.isHealthy ? "正常" : "异常")
                    Spacer()
                    Image(systemName: health.isHealthy ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(health.isHealthy ? .green : .orange)
                }
                StatRow(icon: "photo.badge.exclamationmark",
                        label: "缺失图片",
                        value: "\(health.recordsWithMissingImages)")
                StatRow(icon: "trash",
                        label: "孤立文件",
                        value: "\(health.orphanedImages)")
            }
        }
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMetrics() }
    }

    // MARK: - Metrics

    private func loadMetrics() async {
        let allRecords = (try? context.fetch(FetchDescriptor<Record>())) ?? []
        recordCount = allRecords.filter { !$0.isTrashed }.count
        trashedCount = allRecords.filter { $0.isTrashed }.count
        photoCount = allRecords.reduce(0) { $0 + $1.imagePaths.count }
        imageCacheCount = ImageCacheService.shared.cacheCount
        backupCount = BackupService.existingBackups().count
        health = await IntegrityService.computeHealth(context: context)
        databaseSize = health.databaseSizeBytes
        imagesSize = health.imagesSizeBytes

        // Approximate memory
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            memoryString = byteFormatter.string(fromByteCount: Int64(info.resident_size))
        } else {
            memoryString = "N/A"
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DebugView()
            .modelContainer(for: Record.self, inMemory: true)
    }
}
#endif
