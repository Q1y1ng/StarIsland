import SwiftUI
import PhotosUI

// MARK: - Camera Picker

/// `UIImagePickerController` wrapper for taking a photo.
///
/// - Important: Do **not** call `picker.dismiss()` inside the coordinator —
///   SwiftUI's `.fullScreenCover` manages presentation.  Set `isPresented`
///   to `false` instead; SwiftUI handles the dismiss cleanly.
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            // Camera unavailable — return a no-op picker; the parent
            // button in AddRecordView already guards this path, so this
            // is just a belt‑and‑suspenders safety net.
            print("[Camera] sourceType .camera NOT available")
            return picker
        }

        print("[Camera] sourceType .camera available, presenting picker")
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    // MARK: Coordinator

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
                                UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            print("[Camera] didFinishPicking")

            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                parent.imageData = data
            }

            // ⚠️  Do NOT call picker.dismiss() — SwiftUI controls
            //     the fullScreenCover lifecycle.  Toggle the binding
            //     instead and let SwiftUI dismiss.
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            print("[Camera] didCancel")
            parent.isPresented = false
        }
    }
}

// MARK: - Photos Picker Wrapper

/// Bridges `PhotosPicker` selection into saved image filenames.
struct ImagePickerView: View {
    @Binding var imagePaths: [String]
    let maxSelection: Int

    @State private var selectedItems: [PhotosPickerItem] = []

    private var remaining: Int { max(0, maxSelection - imagePaths.count) }

    var body: some View {
        PhotosPicker(
            selection: $selectedItems,
            maxSelectionCount: remaining,
            matching: .images
        ) {
            Label("相册", systemImage: "photo.on.rectangle")
        }
        .disabled(remaining == 0)
        .onChange(of: selectedItems) { _, newItems in
            loadItems(newItems)
        }
    }

    // MARK: - Load

    private func loadItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }

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
                selectedItems = []
            }
        }
    }
}
