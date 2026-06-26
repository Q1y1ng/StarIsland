import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Add Record View

/// Modal sheet for creating a new time-slice record (Phase 2 Capture System).
///
/// ## Quick Capture
/// - TextEditor auto-focuses on appear
/// - Keyboard opens immediately — no tap needed
/// - Save + dismiss is one tap away
/// - Target: 3 seconds per record
///
/// ## Capabilities
/// - Mood selection via ``MoodSelectorView``
/// - Camera capture (up to 9 images)
/// - Photo library selection (up to 9 images)
/// - Location auto-resolution via ``LocationService``
struct AddRecordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var selectedMood: Mood? = .neutral
    @State private var imagePaths: [String] = []
    @State private var showingCamera = false
    @State private var cameraImageData: Data?
    @State private var isSaving = false
    @State private var cameraError: String?
    @State private var showingPhotoFallback = false
    @State private var fallbackPhotoItems: [PhotosPickerItem] = []

    // ── Location state ────────────────────────────────────────────
    @State private var locationName: String?
    @State private var locationLatitude: Double?
    @State private var locationLongitude: Double?
    @State private var isLocationEnabled = true
    @State private var isFetchingLocation = false

    @FocusState private var isFocused: Bool

    private let locationService = LocationService.shared
    private let maxImages = 9

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Mood selector ──────────────────────────────────
                MoodSelectorView(selection: $selectedMood)

                Divider()

                // ── Location module ────────────────────────────────
                locationModule
                    .padding(.horizontal, AppTheme.spacing.xlarge)
                    .padding(.vertical, AppTheme.spacing.small)

                Divider()

                // ── Image strip ────────────────────────────────────
                if !imagePaths.isEmpty {
                    imageStrip
                    Divider()
                }

                // ── Text editor ────────────────────────────────────
                textEditor
            }
            .navigationTitle("新记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker(imageData: $cameraImageData, isPresented: $showingCamera)
                    .ignoresSafeArea()
                    .onDisappear { handleCameraImage() }
            }
            .alert("相机不可用", isPresented: .init(
                get: { cameraError != nil },
                set: { if !$0 { cameraError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(cameraError ?? "")
            }
            .photosPicker(
                isPresented: $showingPhotoFallback,
                selection: $fallbackPhotoItems,
                maxSelectionCount: maxImages - imagePaths.count,
                matching: .images
            )
            .onChange(of: fallbackPhotoItems) { _, items in
                loadFallbackPhotos(items)
            }
        }
        .onAppear {
            // Quick Capture: auto-focus
            isFocused = true
        }
    }

    // MARK: - Text Editor

    private var textEditor: some View {
        TextEditor(text: $text)
            .font(.body)
            .focused($isFocused)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("记录这一刻...")
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
        ImageGridView(imagePaths: imagePaths, maxDisplay: 9)
            .frame(height: 260)
            .clipped()
            .padding(.horizontal, AppTheme.spacing.xlarge)
            .padding(.vertical, AppTheme.spacing.small)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") {
                // Clean up unsaved images
                ImageStorageService.delete(imagePaths)
                dismiss()
            }
        }

        // ── Camera ────────────────────────────────────────────
        ToolbarItem(placement: .principal) {
            HStack(spacing: AppTheme.spacing.medium) {
                VoiceRecordButton { transcription in
                    if text.isEmpty {
                        text = transcription
                    } else {
                        text = text + "\n" + transcription
                    }
                }

                Button {
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                        print("[AddRecord] camera unavailable, falling back to photo picker")
                        showingPhotoFallback = true
                        return
                    }
                    print("[AddRecord] presenting camera (existing images: \(imagePaths.count))")
                    showingCamera = true
                } label: {
                    Image(systemName: "camera.fill")
                }
                .disabled(imagePaths.count >= maxImages)

                ImagePickerView(
                    imagePaths: $imagePaths,
                    maxSelection: maxImages
                )
            }
        }

        // ── Save ──────────────────────────────────────────────
        ToolbarItem(placement: .confirmationAction) {
            Button("保存") { saveRecord() }
                .disabled(
                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isSaving
                )
                .fontWeight(.semibold)
        }
    }

    // MARK: - Location Module

    @ViewBuilder
    private var locationModule: some View {
        VStack(spacing: AppTheme.spacing.small) {
            HStack {
                // Toggle
                Toggle(isOn: $isLocationEnabled) {
                    HStack(spacing: AppTheme.spacing.medium) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(isLocationEnabled ? Color.blue : Color.secondary.opacity(0.5))
                            .font(.subheadline)
                        Text("记录位置")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
                .toggleStyle(.switch)
            }

            if isLocationEnabled {
                HStack(spacing: AppTheme.spacing.medium) {
                    if isFetchingLocation {
                        HStack(spacing: AppTheme.spacing.small) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("正在获取位置...")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    } else if let name = locationName {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "location.slash")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("未知地点")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button {
                        fetchLocation()
                    } label: {
                        Text("重新获取")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .disabled(isFetchingLocation)
                }
                .padding(.leading, AppTheme.spacing.xxlarge)
            }
        }
        .onAppear {
            if isLocationEnabled {
                fetchLocation()
            }
        }
    }

    // MARK: - Fetch Location

    private func fetchLocation() {
        print("[AddRecord] fetchLocation: start")
        isFetchingLocation = true
        Task {
            let result = await locationService.requestLocation()
            await MainActor.run {
                print("[AddRecord] fetchLocation: done name=\(result.locationName ?? "nil") lat=\(result.latitude ?? -1) lng=\(result.longitude ?? -1)")
                locationName = result.locationName
                locationLatitude = result.latitude
                locationLongitude = result.longitude
                isFetchingLocation = false
            }
        }
    }

    // MARK: - Actions

    private func handleCameraImage() {
        guard let data = cameraImageData,
              let filename = ImageStorageService.save(data) else {
            print("[AddRecord] handleCameraImage: no data or save failed (data=\(cameraImageData != nil))")
            cameraImageData = nil
            return
        }
        print("[AddRecord] camera image saved: \(filename) (\(data.count)B)")
        cameraImageData = nil
        imagePaths.append(filename)
    }

    private func loadFallbackPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let remaining = maxImages - imagePaths.count
        Task {
            var newPaths: [String] = []
            for item in items where newPaths.count < remaining {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let filename = ImageStorageService.save(data) {
                    newPaths.append(filename)
                }
            }
            await MainActor.run {
                imagePaths.append(contentsOf: newPaths)
                fallbackPhotoItems = []
            }
        }
    }

    private func saveRecord() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true

        print("[AddRecord] save: text=\(trimmed.prefix(50)) images=\(imagePaths.count) location=\(locationName ?? "nil") mood=\(selectedMood?.title ?? "nil")")

        let record = Record(
            text: trimmed,
            mood: selectedMood,
            locationName: isLocationEnabled ? (locationName ?? "未知地点") : nil,
            latitude: isLocationEnabled ? locationLatitude : nil,
            longitude: isLocationEnabled ? locationLongitude : nil,
            imagePaths: imagePaths
        )

        modelContext.insert(record)
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
    AddRecordView()
        .modelContainer(for: Record.self, inMemory: true)
}
