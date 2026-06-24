import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Settings View

/// Apple Settings‑style configuration page.
///
/// v1.0 RC sections:
/// - 回收站
/// - 同步（预留）
/// - 外观（主题 / App 图标）
/// - 数据备份
/// - 数据健康
/// - 关于
struct SettingsView: View {
    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<Record> { !$0.isTrashed },
        sort: \Record.timestamp, order: .reverse
    )
    private var allRecords: [Record]

    @Query(
        filter: #Predicate<Record> { $0.isTrashed },
        sort: \Record.trashedAt, order: .reverse
    )
    private var trashedRecords: [Record]

    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showingExporter = false
    @State private var importResult: ImportResult?
    @State private var showingImportAlert = false
    @State private var importError: Error?
    @State private var showingErrorAlert = false
    @State private var backupCount: Int = 0

    // MARK: - Body

    var body: some View {
        Form {
            // ── Recycle Bin ─────────────────────────────────────────
            recycleSection

            // ── Sync ────────────────────────────────────────────────
            syncSection

            // ── Appearance ──────────────────────────────────────────
            appearanceSection

            // ── Data Backup ─────────────────────────────────────────
            backupSection

            // ── Data Health ─────────────────────────────────────────
            healthSection

            // ── About ───────────────────────────────────────────────
            aboutSection
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadBackupCount)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("导入完成", isPresented: $showingImportAlert) {
            Button("好", role: .cancel) {}
        } message: {
            if let result = importResult {
                Text(result.description)
            }
        }
        .alert("导入失败", isPresented: $showingErrorAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(importError?.localizedDescription ?? "未知错误")
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportURL.flatMap { BackupDocument(url: $0) },
            contentType: .zip,
            defaultFilename: exportURL?.lastPathComponent ?? "StarIslandBackup.zip"
        ) { result in
            if let url = exportURL {
                try? FileManager.default.removeItem(at: url)
                exportURL = nil
            }
        }
    }

    // MARK: - Recycle Bin Section

    private var recycleSection: some View {
        Section {
            NavigationLink(destination: RecycleBinView()) {
                HStack {
                    Image(systemName: "trash.fill")
                        .foregroundStyle(.red)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("回收站")
                            .font(.body)
                        Text("\(trashedRecords.count) 条记录 · 30 天自动清理")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        } header: {
            Label("数据管理", systemImage: "externaldrive")
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        Section {
            HStack {
                Image(systemName: "icloud")
                    .foregroundStyle(.blue)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud 同步")
                        .font(.body)
                    Text("v1.0 暂不支持")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Label("同步", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    // MARK: - Appearance Section

    @State private var showingIconPicker = false

    private var appearanceSection: some View {
        Section {
            // ── Theme picker ────────────────────────────────────────
            Picker(selection: Binding(
                get: { SettingsStorage.resolvedThemeMode },
                set: { SettingsStorage.resolvedThemeMode = $0 }
            )) {
                ForEach(ThemeMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            } label: {
                HStack {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.blue)
                    Text("主题")
                }
            }

            // ── App Icon ────────────────────────────────────────────
            NavigationLink(destination: IconPickerView()) {
                HStack {
                    Image(systemName: "app.gift")
                        .foregroundStyle(.blue)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App 图标")
                            .font(.body)
                        let name = iconDisplayName(SettingsStorage.selectedIcon)
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            #if DEBUG
            // ── Debug (DEBUG only) ──────────────────────────────────
            NavigationLink(destination: DebugView()) {
                HStack {
                    Image(systemName: "ladybug.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                    Text("Debug")
                        .font(.body)
                }
            }
            #endif
        } header: {
            Label("外观", systemImage: "paintbrush")
        }
    }

    // MARK: - Backup Section

    private var backupSection: some View {
        Section {
            // ── Export ──────────────────────────────────────────────
            Button {
                startExport()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.blue)
                    Text("导出数据")
                    Spacer()
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isExporting)

            // ── Import ──────────────────────────────────────────────
            Button {
                isImporting = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(.blue)
                    Text("导入数据")
                }
            }

            // ── Auto backup toggle ──────────────────────────────────
            Toggle(isOn: Binding(
                get: { SettingsStorage.autoBackupEnabled },
                set: {
                    SettingsStorage.autoBackupEnabled = $0
                    if $0 { AutoBackupManager.shared.scheduleNext() }
                }
            )) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.blue)
                    Text("自动备份")
                }
            }

            // ── Backup limit ────────────────────────────────────────
            if SettingsStorage.autoBackupEnabled {
                Stepper(value: Binding(
                    get: { SettingsStorage.backupLimit },
                    set: { SettingsStorage.backupLimit = max(1, min(90, $0)) }
                ), in: 1 ... 90) {
                    HStack {
                        Image(systemName: "tray.full")
                            .foregroundStyle(.blue)
                        Text("保留 \(SettingsStorage.backupLimit) 个备份")
                    }
                }
            }

            // ── Backup count ────────────────────────────────────────
            if backupCount > 0 {
                HStack {
                    Image(systemName: "archivebox")
                        .foregroundStyle(.blue)
                    Text("本地备份")
                    Spacer()
                    Text("\(backupCount) 个")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("数据备份", systemImage: "externaldrive.badge.checkmark")
        }
    }

    // MARK: - Health Section

    private var healthSection: some View {
        Section {
            NavigationLink(destination: DataHealthView()) {
                HStack {
                    Image(systemName: "heart.text.square")
                        .foregroundStyle(.red)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("数据健康")
                            .font(.body)
                        Text("检查图片、数据库完整性")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        } header: {
            Label("维护", systemImage: "wrench.adjustable")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            // App name + icon
            HStack(spacing: AppTheme.spacing.medium) {
                Image(systemName: "star.fill")
                    .font(.title)
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("StarIsland")
                        .font(.body)
                        .fontWeight(.semibold)
                    Text("Version \(appVersion) (Build \(buildNumber))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, AppTheme.spacing.xxsmall)

            // Record stats
            let activeRecords = allRecords
            let photoCount = activeRecords.reduce(0) { $0 + $1.imagePaths.count }

            StatRow(icon: "doc.text",
                    label: "记录总数",
                    value: "\(activeRecords.count)")

            StatRow(icon: "photo",
                    label: "照片总数",
                    value: "\(photoCount)")

            StatRow(icon: "calendar",
                    label: "第一条记录",
                    value: activeRecords.last?.timestamp.dayTitle ?? "无")

            StatRow(icon: "archivebox",
                    label: "数据版本",
                    value: "v1")
        } header: {
            Label("关于 StarIsland", systemImage: "info.circle")
        }
    }

    // MARK: - Actions

    private func startExport() {
        isExporting = true
        Task {
            do {
                let url = try await BackupService.exportBackup(context: context)
                await MainActor.run {
                    exportURL = url
                    isExporting = false
                    showingExporter = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    importError = error
                    showingErrorAlert = true
                }
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else {
                importError = BackupError.missingRecords
                showingErrorAlert = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            Task {
                do {
                    let result = try await BackupService.importBackup(from: url,
                                                                       context: context)
                    await MainActor.run {
                        importResult = result
                        showingImportAlert = true
                        loadBackupCount()
                    }
                } catch {
                    await MainActor.run {
                        importError = error
                        showingErrorAlert = true
                    }
                }
            }

        case .failure(let error):
            importError = error
            showingErrorAlert = true
        }
    }

    // MARK: - Helpers

    private func loadBackupCount() {
        backupCount = BackupService.existingBackups().count
    }

    private func iconDisplayName(_ key: String) -> String {
        switch key {
        case "default":    return "默认"
        case "DeepSpace": return "Deep Space"
        case "White":     return "White"
        default:          return "默认"
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Icon Picker View

/// Simple list of available app icons.
private struct IconPickerView: View {
    @State private var selectedIcon = SettingsStorage.selectedIcon

    private let icons: [(key: String, name: String, symbol: String)] = [
        ("default",    "默认",      "star.fill"),
        ("DeepSpace", "Deep Space", "moon.stars.fill"),
        ("White",     "White",      "snowflake"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(icons, id: \.key) { icon in
                    Button {
                        selectIcon(icon.key)
                    } label: {
                        HStack(spacing: AppTheme.spacing.medium) {
                            Image(systemName: icon.symbol)
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .frame(width: 28)

                            Text(icon.name)
                                .font(.body)
                                .foregroundStyle(.primary)

                            Spacer()

                            if selectedIcon == icon.key {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            } footer: {
                Text("切换图标会立即生效。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .navigationTitle("App 图标")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func selectIcon(_ key: String) {
        #if !targetEnvironment(simulator)
        if key == "default" {
            UIApplication.shared.setAlternateIconName(nil)
        } else {
            UIApplication.shared.setAlternateIconName(key)
        }
        #endif
        selectedIcon = key
        SettingsStorage.selectedIcon = key
    }
}

// MARK: - Stat Row

/// Simple key‑value row used in About and Health sections.
struct StatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Backup Document (File Exporter)

/// Wraps a ZIP file URL as a `FileDocument` for `.fileExporter`.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    let url: URL

    init(url: URL) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(url: url)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
            .modelContainer(for: Record.self, inMemory: true)
    }
}
