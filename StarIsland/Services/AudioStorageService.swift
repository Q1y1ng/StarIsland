import Foundation

// MARK: - Audio Storage Service

/// Persistent audio file management.
///
/// Mirrors the `ImageStorageService` pattern:
/// - Files stored under `Application Support/audio/`
/// - Filenames are UUID‑based with `.m4a` extension
/// - Save returns the filename string, not a URL
///
/// ## Thread safety
/// All methods are thread‑safe as long as `FileManager` operations on
/// the `audio/` directory are not called concurrently from multiple
/// threads with the same filename.  In practice, the UI serialises
/// record / delete actions on the main actor.
enum AudioStorageService {
    /// Absolute URL of the `audio/` directory.
    /// Creates the directory on first access.
    static let audioDir: URL = {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = base.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                  withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Save

    /// Write audio data to disk.
    /// - Parameter data: Raw audio bytes (AAC / m4a container).
    /// - Returns: The filename (e.g. `"e12f4a32....m4a"`), or `nil` on failure.
    @discardableResult
    static func save(_ data: Data) -> String? {
        let filename = "\(UUID().uuidString.lowercased()).m4a"
        let url = audioDir.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return filename
        } catch {
            print("[AudioStorage] save failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - URL

    /// Build the absolute URL for a stored audio filename.
    static func url(for filename: String) -> URL {
        audioDir.appendingPathComponent(filename)
    }

    // MARK: - Delete

    /// Remove a single audio file from disk.
    static func delete(_ filename: String) {
        let url = self.url(for: filename)
        try? FileManager.default.removeItem(at: url)
    }

    /// Remove multiple audio files from disk.
    static func delete(_ filenames: [String]) {
        for name in filenames { delete(name) }
    }
}
