import Foundation
import SwiftData

// MARK: - Record View Model

/// Lightweight mediator between views and SwiftData.
///
/// Phase 2 additions:
/// - Image management helpers (cleanup orphaned files)
/// - Future: search / filter / export
@MainActor
final class RecordViewModel: ObservableObject {
    // MARK: - Published State (reserved)

    @Published var searchText: String = ""
    @Published var isExporting: Bool = false

    // MARK: - Image Management

    /// Remove image files that are no longer referenced by any record.
    /// Call this after batch deletes to reclaim disk space.
    /// - Parameter context: SwiftData model context for record queries.
    func cleanOrphanedImages(context: ModelContext) {
        let allPaths = getAllImagePaths(context: context)
        let referenced = Set(allPaths)

        let fileManager = FileManager.default
        let imagesDir = ImageStorageService.imagesDir

        guard let files = try? fileManager.contentsOfDirectory(atPath: imagesDir.path)
        else { return }

        for file in files where !referenced.contains(file) {
            ImageStorageService.delete(file)
        }
    }

    /// Remove audio files that are no longer referenced by any record.
    func cleanOrphanedAudio(context: ModelContext) {
        let allPaths = getAllAudioPaths(context: context)
        let referenced = Set(allPaths)

        let fileManager = FileManager.default
        let audioDir = AudioStorageService.audioDir

        guard let files = try? fileManager.contentsOfDirectory(atPath: audioDir.path)
        else { return }

        for file in files where !referenced.contains(file) {
            AudioStorageService.delete(file)
        }
    }

    // MARK: - Helpers

    private func getAllImagePaths(context: ModelContext) -> [String] {
        let descriptor = FetchDescriptor<Record>()
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.flatMap(\.imagePaths)
    }

    private func getAllAudioPaths(context: ModelContext) -> [String] {
        let descriptor = FetchDescriptor<Record>()
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.flatMap(\.audioPaths)
    }
}
