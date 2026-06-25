import SwiftUI
import PhotosUI

// MARK: - Camera Picker

/// `UIImagePickerController` wrapper for taking a photo.
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var imageData: Data?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        // Guard: camera must be available on this device
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            // Return a no-op picker; the coordinator logs the failure
            let picker = UIImagePickerController()
            picker.delegate = context.coordinator
            return picker
        }

        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
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
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                parent.imageData = data
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
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
