import SwiftUI
import SwiftData

// MARK: - Data Health View

/// Database and filesystem integrity check results.
///
/// Shows the output of ``IntegrityService.computeHealth(context:)`` with
/// clear pass / warn indicators.
struct DataHealthView: View {
    @Environment(\.modelContext) private var context

    @State private var health: DatabaseHealth = .zero
    @State private var isChecking = false

    private let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    // MARK: - Body

    var body: some View {
        Form {
            // ── Status ──────────────────────────────────────────────
            Section {
                HStack {
                    Image(systemName: health.isHealthy ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(health.isHealthy ? .green : .orange)
                        .font(.title2)
                    Text(health.isHealthy ? "数据正常" : "发现异常")
                        .font(.headline)
                }
                .padding(.vertical, AppTheme.spacing.xxsmall)
            }

            // ── Details ─────────────────────────────────────────────
            Section("完整性检查") {
                StatRow(icon: "doc.text",
                        label: "记录总数",
                        value: "\(health.totalRecords)")

                HStack {
                    StatRow(icon: "photo",
                            label: "缺失图片记录",
                            value: "\(health.recordsWithMissingImages)")
                    Spacer()
                    if health.recordsWithMissingImages > 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                HStack {
                    StatRow(icon: "trash",
                            label: "孤立文件",
                            value: "\(health.orphanedImages)")
                    Spacer()
                    if health.orphanedImages > 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .help("已自动清理")
                    }
                }

                HStack {
                    StatRow(icon: "arrow.triangle.2.circlepath",
                            label: "重复 SyncID",
                            value: "\(health.duplicateSyncIds)")
                    Spacer()
                    if health.duplicateSyncIds > 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .help("已自动修复")
                    }
                }
            }

            // ── Storage ─────────────────────────────────────────────
            Section("存储") {
                StatRow(icon: "internaldrive",
                        label: "数据库大小",
                        value: byteFormatter.string(fromByteCount: health.databaseSizeBytes))

                StatRow(icon: "photo.on.rectangle.angled",
                        label: "图片占用",
                        value: byteFormatter.string(fromByteCount: health.imagesSizeBytes))

                StatRow(icon: "waveform",
                        label: "音频占用",
                        value: byteFormatter.string(fromByteCount: health.audioSizeBytes))

                let total = health.databaseSizeBytes + health.imagesSizeBytes + health.audioSizeBytes
                StatRow(icon: "archivebox",
                        label: "总计",
                        value: byteFormatter.string(fromByteCount: total))
            }

            // ── Backups ─────────────────────────────────────────────
            Section("备份") {
                let backups = BackupService.existingBackups()
                StatRow(icon: "archivebox",
                        label: "本地备份数",
                        value: "\(backups.count)")

                if let latest = backups.first {
                    let date = (try? latest.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate) ?? Date()
                    StatRow(icon: "clock",
                            label: "最后备份",
                            value: date.dayTitle)
                } else {
                    StatRow(icon: "clock",
                            label: "最后备份",
                            value: "无")
                }
            }
        }
        .navigationTitle("数据健康")
        .navigationBarTitleDisplayMode(.inline)
        .task { await check() }
    }

    // MARK: - Check

    private func check() async {
        isChecking = true
        health = await IntegrityService.computeHealth(context: context)
        isChecking = false
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DataHealthView()
            .modelContainer(for: Record.self, inMemory: true)
    }
}
