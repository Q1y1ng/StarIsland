import UIKit

// MARK: - Image Storage Service

/// Manages reading / writing images to `Application Support/images/`.
///
/// The database stores only the **filename** (e.g. `"E12F4A32-....jpg"`).
/// Callers reconstruct the full URL via ``url(for:)`` when displaying.
enum ImageStorageService {
    /// Directory where all record images live.
    static let imagesDir: URL = {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let dir = base.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                  withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Public API

    /// Persist JPEG data to disk and return the filename.
    /// - Parameter data: Raw JPEG image data.
    /// - Returns: Unique filename (e.g. `"E12F4A32-....jpg"`), or `nil` on failure.
    @discardableResult
    static func save(_ data: Data) -> String? {
        let filename = "\(UUID().uuidString.lowercased()).jpg"
        let url = imagesDir.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    /// Full file URL for a stored image filename.
    static func url(for filename: String) -> URL {
        imagesDir.appendingPathComponent(filename)
    }

    /// Remove a single image file from disk.
    static func delete(_ filename: String) {
        let url = self.url(for: filename)
        try? FileManager.default.removeItem(at: url)
    }

    /// Remove multiple images from disk.
    static func delete(_ filenames: [String]) {
        for name in filenames {
            delete(name)
        }
    }
}
