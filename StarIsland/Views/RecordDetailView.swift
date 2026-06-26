import SwiftUI
import SwiftData

// MARK: - Record Detail View

/// Full detail view for a single time-slice record.
///
/// Apple Journal style with generous whitespace, system fonts, and no cards.
///
/// ## Phase 2.5 — Soft Delete
/// The toolbar includes a delete button that marks the record as trashed
/// (`isTrashed = true`) instead of permanently removing it.  A confirmation
/// alert prevents accidental taps.
struct RecordDetailView: View {
    let record: Record

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingDeleteAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.huge) {
                dateHeader
                metadataSection

                Divider()

                bodyContent
                imageSection
            }
            .padding(AppTheme.spacing.xxxlarge)
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
        .toolbar { toolbarContent }
        .alert("删除记录", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { softDelete() }
        } message: {
            Text("这条记录将被隐藏，不会永久删除。")
        }
    }

    // MARK: - Date Header

    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xsmall) {
            Text(record.timestamp.dayTitle)
                .font(.largeTitle)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Text(record.timestamp.weekday)
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(record.timestamp.timeOnly)
                .font(.system(.title, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .padding(.top, AppTheme.spacing.small)
        }
    }

    // MARK: - Metadata

    @ViewBuilder
    private var metadataSection: some View {
        let hasLocation = record.locationName?.isEmpty == false
        let hasMood = record.mood != nil

        if hasLocation || hasMood {
            VStack(alignment: .leading, spacing: AppTheme.spacing.medium) {
                if hasLocation, let location = record.locationName {
                    Label(location, systemImage: "location.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let mood = record.mood {
                    HStack(spacing: AppTheme.spacing.small) {
                        Text(mood.emoji)
                            .font(.title2)
                        Text(mood.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Body

    private var bodyContent: some View {
        Text(record.text)
            .font(.body)
            .lineSpacing(AppTheme.spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Images

    @ViewBuilder
    private var imageSection: some View {
        if !record.imagePaths.isEmpty {
            let _ = print("[RecordDetail] images: count=\(record.imagePaths.count) maxHeight=240")
            ImageGridView(imagePaths: record.imagePaths)
                .frame(maxWidth: .infinity, maxHeight: 240)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .destructiveAction) {
            Button {
                showingDeleteAlert = true
            } label: {
                Image(systemName: "trash")
            }
            .tint(.red)
        }
    }

    // MARK: - Soft Delete

    private func softDelete() {
        guard !record.isTrashed else { return }

        withAnimation(.easeInOut(duration: AppTheme.animationDuration.delete)) {
            record.isTrashed = true
            record.trashedAt = Date()
            record.updatedAt = Date()
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RecordDetailView(
            record: Record(
                text: """
                今天在海边散步，看到了最美的日落。
                天空从橙色渐变成紫色，海浪声让人平静。
                这是我今年见过最治愈的画面。
                """,
                mood: .happy,
                locationName: "滨海路海岸"
            )
        )
    }
}
