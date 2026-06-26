import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Add Record View

/// Modal sheet for creating a new time-slice record (Phase T4.6 UX).
///
/// ## Layout (Apple Journal style)
/// ```
/// Emoji picker
/// Toolbar (camera / photo library)
/// Location (tappable → LocationPickerView)
/// Title text
/// Body text
/// ──────────────────────────────
/// Image strip (horizontal scroll, 110×110)
/// ```
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
    @State private var showingLocationPicker = false

    // ── Image viewer state ────────────────────────────────────────
    @State private var viewerIndex: Int?
    @State private var showViewer = false

    @FocusState private var isFocused: Bool

    private let locationService = LocationService.shared
    private let maxImages = 9

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Mood selector ──────────────────────────────
                    moodSection

                    Divider()
                        .padding(.horizontal, AppTheme.spacing.xlarge)

                    // ── Toolbar (camera / photo) ──────────────────
                    toolbarSection
                        .padding(.horizontal, AppTheme.spacing.xlarge)
                        .padding(.vertical, AppTheme.spacing.medium)

                    Divider()
                        .padding(.horizontal, AppTheme.spacing.xlarge)

                    // ── Location (tappable) ───────────────────────
                    locationSection
                        .padding(.horizontal, AppTheme.spacing.xlarge)
                        .padding(.vertical, AppTheme.spacing.medium)

                    Divider()
                        .padding(.horizontal, AppTheme.spacing.xlarge)

                    // ── Text editor ───────────────────────────────
                    textSection
                        .padding(.horizontal, AppTheme.spacing.xlarge)
                        .padding(.top, AppTheme.spacing.medium)

                    // ── Image strip (always at bottom) ────────────
                    if !imagePaths.isEmpty || imagePaths.count < maxImages {
                        imageStrip
                            .padding(.top, AppTheme.spacing.medium)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
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
            .sheet(isPresented: $showingLocationPicker) {
                LocationPickerView(
                    selectedName: $locationName,
                    selectedLatitude: $locationLatitude,
                    selectedLongitude: $locationLongitude
                )
            }
            .fullScreenCover(isPresented: $showViewer) {
                if let idx = viewerIndex {
                    PhotoViewer(imagePaths: imagePaths, initialIndex: idx)
                }
            }
        }
        .onAppear {
            isFocused = true
            if isLocationEnabled && locationName == nil {
                fetchLocation()
            }
        }
    }

    // MARK: - Mood Section

    private var moodSection: some View {
        VStack(spacing: AppTheme.spacing.small) {
            // Large emoji display
            if let mood = selectedMood {
                Text(mood.emoji)
                    .font(.system(size: 48))
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: selectedMood)
            }

            MoodSelectorView(selection: $selectedMood)
                .padding(.horizontal, AppTheme.spacing.xlarge)
        }
        .padding(.vertical, AppTheme.spacing.medium)
    }

    // MARK: - Toolbar Section

    private var toolbarSection: some View {
        HStack(spacing: AppTheme.spacing.xlarge) {
            // Camera button
            Button {
                guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                    print("[AddRecord] camera unavailable, falling back to photo picker")
                    showingPhotoFallback = true
                    return
                }
                print("[AddRecord] presenting camera (existing images: \(imagePaths.count))")
                showingCamera = true
            } label: {
                Label("拍照", systemImage: "camera.fill")
                    .font(.subheadline)
            }
            .disabled(imagePaths.count >= maxImages)

            // Photo library button
            ImagePickerView(
                imagePaths: $imagePaths,
                maxSelection: maxImages
            )

            Spacer()

            // Voice record button
            VoiceRecordButton { transcription in
                if text.isEmpty {
                    text = transcription
                } else {
                    text = text + "\n" + transcription
                }
            }
        }
    }

    // MARK: - Location Section

    @ViewBuilder
    private var locationSection: some View {
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
                    // Tappable location name → opens LocationPickerView
                    Button {
                        showingLocationPicker = true
                    } label: {
                        HStack(spacing: AppTheme.spacing.small) {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    HStack(spacing: AppTheme.spacing.small) {
                        Image(systemName: "location.slash")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("未知地点")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if !isFetchingLocation {
                    Button {
                        fetchLocation()
                    } label: {
                        Text("重新获取")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .disabled(isFetchingLocation)
                }
            }
            .padding(.leading, AppTheme.spacing.xxlarge)
        }
    }

    // MARK: - Text Section

    private var textSection: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .frame(minHeight: 120)
            .focused($isFocused)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("记录这一刻...")
                        .foregroundStyle(.tertiary)
                        .padding(.top, AppTheme.spacing.medium)
                        .padding(.leading, AppTheme.spacing.xsmall)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: - Image Strip

    private var imageStrip: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.small) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.spacing.medium) {
                    // Existing images
                    ForEach(imagePaths.indices, id: \.self) { idx in
                        imageThumb(filename: imagePaths[idx], index: idx)
                    }

                    // Add button (last cell)
                    if imagePaths.count < maxImages {
                        addImageButton
                    }
                }
                .padding(.horizontal, AppTheme.spacing.xlarge)
            }
        }
        .frame(height: 130)
    }

    private func imageThumb(filename: String, index: Int) -> some View {
        LocalImageThumb(filename: filename)
            .frame(width: 110, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
            .overlay(alignment: .topTrailing) {
                // Delete button
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        imagePaths.remove(at: index)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .background(Circle().fill(.black.opacity(0.5)))
                        .padding(4)
                }
            }
            .onTapGesture {
                viewerIndex = index
                showViewer = true
            }
            .transition(.scale.combined(with: .opacity))
    }

    private var addImageButton: some View {
        Button {
            showImagePicker()
        } label: {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.tertiary, lineWidth: 1)
                .frame(width: 110, height: 110)
                .overlay {
                    VStack(spacing: AppTheme.spacing.small) {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("\(imagePaths.count)/\(maxImages)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func showImagePicker() {
        let remaining = maxImages - imagePaths.count
        guard remaining > 0 else { return }

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showingCamera = true
        } else {
            showingPhotoFallback = true
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") {
                ImageStorageService.delete(imagePaths)
                dismiss()
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("保存") { saveRecord() }
                .disabled({
                    let noText = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let noImages = imagePaths.isEmpty
                    let noLocation = !(isLocationEnabled && (locationName != nil))
                    return (noText && noImages && noLocation) || isSaving
                }())
                .fontWeight(.semibold)
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            imagePaths.append(filename)
        }
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
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    imagePaths.append(contentsOf: newPaths)
                }
                fallbackPhotoItems = []
            }
        }
    }

    private func saveRecord() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = !trimmed.isEmpty
        let hasImages = !imagePaths.isEmpty
        let hasLocation = isLocationEnabled && locationName != nil
        guard hasText || hasImages || hasLocation else { return }

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

// MARK: - Local Image Thumb

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
