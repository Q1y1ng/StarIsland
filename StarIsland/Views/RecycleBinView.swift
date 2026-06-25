import SwiftUI
import SwiftData

// MARK: - Recycle Bin View

/// Soft‑deleted records with restore and permanent delete support.
///
/// ```
/// ┌──────────────────────────────────┐
///  🗑 回收站
///  23 条记录 · 30 天自动清理
/// ┌──────────────────────────────────┐
/// │ 2026年06月20日 周四               │
/// │  ▒▒▒▒▒ 记录正文...      删除: 4d  │
/// │ 2026年06月18日 周二               │
/// │  ▒▒▒▒▒ 记录正文...      删除: 6d  │
/// │ 2026年06月15日 周六               │
/// │  ▒▒▒▒▒ 记录正文...      删除: 9d  │
/// │           ...                     │
/// └──────────────────────────────────┘
/// ```
///
/// Records are automatically purged after 30 days.
struct RecycleBinView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<Record> { $0.isTrashed },
        sort: \Record.trashedAt, order: .reverse
    )
    private var trashedRecords: [Record]

    @State private var selectedIDs = Set<UUID>()
    @State private var isEditing = false
    @State private var confirmPermanentDelete = false
    @State private var confirmRestoreAll = false
    @State private var confirmEmptyAll = false
    @State private var recordToDelete: Record?

    private let autoPurgeDays = 30

    // MARK: - Body

    var body: some View {
        Group {
            if trashedRecords.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle("回收站")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .alert("永久删除", isPresented: $confirmPermanentDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let record = recordToDelete {
                    permanentlyDelete(record)
                    recordToDelete = nil
                }
            }
        } message: {
            Text("此操作无法撤销。记录及其照片将被永久删除。")
        }
        .alert("恢复全部", isPresented: $confirmRestoreAll) {
            Button("取消", role: .cancel) {}
            Button("恢复全部") { restoreAll() }
        } message: {
            Text("所有回收站中的记录将被恢复到时间线。")
        }
        .alert("清空回收站", isPresented: $confirmEmptyAll) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { emptyAll() }
        } message: {
            Text("所有记录将被永久删除，无法撤销。")
        }
    }

    // MARK: - Content

    private var content: some View {
        List {
            // ── Stats header ────────────────────────────────────────
            Section {
                HStack {
                    Image(systemName: "trash.fill")
                        .foregroundStyle(.red)
                    Text("\(trashedRecords.count) 条记录")
                    Spacer()
                    Text("\(autoPurgeDays) 天自动清理")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .listRowBackground(Color(.systemGray6))
            }

            // ── Records ─────────────────────────────────────────────
            Section {
                ForEach(trashedRecords) { record in
                    recycleRow(record)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                recordToDelete = record
                                confirmPermanentDelete = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }

                            Button {
                                restoreRecord(record)
                            } label: {
                                Label("恢复", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func recycleRow(_ record: Record) -> some View {
        HStack(spacing: AppTheme.spacing.medium) {
            if isEditing {
                Image(systemName: selectedIDs.contains(record.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedIDs.contains(record.id) ? Color.blue : Color.secondary.opacity(0.5))
                    .onTapGesture {
                        if selectedIDs.contains(record.id) {
                            selectedIDs.remove(record.id)
                        } else {
                            selectedIDs.insert(record.id)
                        }
                    }
            }

            VStack(alignment: .leading, spacing: AppTheme.spacing.xxsmall) {
                // Text preview
                Text(record.text)
                    .font(.body)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                // Date + days since deletion
                HStack(spacing: AppTheme.spacing.small) {
                    Text(record.timestamp.dayTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let trashedAt = record.trashedAt {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("已删除 \(daysSince(trashedAt))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Image count indicator
            if !record.imagePaths.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "photo")
                        .font(.caption2)
                    Text("\(record.imagePaths.count)")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, AppTheme.spacing.xxsmall)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing {
                toggleSelection(record.id)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppTheme.spacing.xlarge) {
            Spacer()
            Text("🗑️")
                .font(.system(size: 56))
            Text("回收站是空的")
                .font(.title3)
                .fontWeight(.semibold)
            Text("删除的记录会在这里保留 \(autoPurgeDays) 天")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !trashedRecords.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? "完成" : "编辑") {
                    withAnimation {
                        isEditing.toggle()
                        if !isEditing { selectedIDs.removeAll() }
                    }
                }
            }

            if isEditing {
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("恢复所选") {
                            restoreSelected()
                        }
                        .disabled(selectedIDs.isEmpty)

                        Spacer()

                        Button("清空所选", role: .destructive) {
                            deleteSelected()
                        }
                        .disabled(selectedIDs.isEmpty)
                    }
                }

                ToolbarItem(placement: .status) {
                    Text("已选 \(selectedIDs.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("恢复全部") {
                            confirmRestoreAll = true
                        }

                        Spacer()

                        Button("清空回收站", role: .destructive) {
                            confirmEmptyAll = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func restoreRecord(_ record: Record) {
        record.isTrashed = false
        record.trashedAt = nil
        record.updatedAt = Date()
        try? modelContext.save()
    }

    private func permanentlyDelete(_ record: Record) {
        ImageStorageService.delete(record.imagePaths)
        modelContext.delete(record)
        try? modelContext.save()
    }

    private func restoreAll() {
        for record in trashedRecords {
            record.isTrashed = false
            record.trashedAt = nil
            record.updatedAt = Date()
        }
        try? modelContext.save()
    }

    private func emptyAll() {
        for record in trashedRecords {
            ImageStorageService.delete(record.imagePaths)
            modelContext.delete(record)
        }
        try? modelContext.save()
    }

    private func restoreSelected() {
        let selected = trashedRecords.filter { selectedIDs.contains($0.id) }
        for record in selected {
            record.isTrashed = false
            record.trashedAt = nil
            record.updatedAt = Date()
        }
        selectedIDs.removeAll()
        try? modelContext.save()
    }

    private func deleteSelected() {
        let selected = trashedRecords.filter { selectedIDs.contains($0.id) }
        for record in selected {
            ImageStorageService.delete(record.imagePaths)
            modelContext.delete(record)
        }
        selectedIDs.removeAll()
        try? modelContext.save()
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func daysSince(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days == 0 { return "今天" }
        return "\(days) 天前"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RecycleBinView()
            .modelContainer(for: Record.self, inMemory: true)
    }
}
