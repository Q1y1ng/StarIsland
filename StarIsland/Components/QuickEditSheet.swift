import SwiftUI
import SwiftData

// MARK: - Quick Edit Sheet

/// Minimal editing sheet triggered by long‑pressing a ``TimelineCell``.
///
/// Supports:
/// - Editing the record text
/// - Changing the mood
/// - Deleting images
///
/// Does NOT navigate to the full detail page.
/// Target: 3‑second edit cycle.
struct QuickEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let record: Record

    @State private var text: String
    @State private var selectedMood: Mood?
    @State private var imagePaths: [String]

    init(record: Record) {
        self.record = record
        _text = State(initialValue: record.text)
        _selectedMood = State(initialValue: record.mood)
        _imagePaths = State(initialValue: record.imagePaths)
    }

    private let maxImages = 9

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Mood selector ──────────────────────────────────
                MoodSelectorView(selection: $selectedMood)

                Divider()

                // ── Image strip ────────────────────────────────────
                if !imagePaths.isEmpty {
                    imageStrip
                    Divider()
                }

                // ── Text editor ────────────────────────────────────
                textEditor
            }
            .navigationTitle("快速编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Text Editor

    private var textEditor: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("修改正文...")
                        .foregroundStyle(.tertiary)
                        .padding(.top, AppTheme.spacing.medium)
                        .padding(.leading, AppTheme.spacing.xsmall)
                        .allowsHitTesting(false)
                }
            }
            .padding(AppTheme.spacing.xlarge)
    }

    // MARK: - Image Strip

    private var imageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.spacing.medium) {
                ForEach(imagePaths, id: \.self) { path in
                    ZStack(alignment: .topTrailing) {
                        LocalImageThumb(filename: path)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius.small))

                        Button {
                            withAnimation {
                                ImageStorageService.delete(path)
                                imagePaths.removeAll { $0 == path }
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .background(Circle().fill(.black.opacity(0.5)))
                        }
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.horizontal, AppTheme.spacing.xlarge)
            .padding(.vertical, AppTheme.spacing.small)
        }
        .frame(height: 80)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("保存") { save() }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .fontWeight(.semibold)
        }
    }

    // MARK: - Actions

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        record.text = trimmed
        record.mood = selectedMood
        record.imagePaths = imagePaths
        record.updatedAt = Date()

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Local Thumbnail

/// Small inline thumbnail for the image strip.
private struct LocalImageThumb: View {
    let filename: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay { ProgressView().controlSize(.mini) }
            }
        }
        .task(priority: .medium) { await load() }
    }

    private func load() async {
        guard image == nil else { return }
        let url = ImageStorageService.url(for: filename)
        let img = await Task.detached(priority: .medium) {
            UIImage(contentsOfFile: url.path)
        }.value
        await MainActor.run { image = img }
    }
}

// MARK: - Preview

#Preview {
    let record = Record(text: "示例记录，可以在编辑长按修改。", mood: .happy)
    QuickEditSheet(record: record)
        .modelContainer(for: Record.self, inMemory: true)
}
