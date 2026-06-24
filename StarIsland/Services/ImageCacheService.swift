import UIKit

// MARK: - Image Cache Service

/// Memory-caches decoded `UIImage` instances so the grid and timeline
/// do not re-read the same file from disk on every appearance.
///
/// Backed by `NSCache` — the system evicts entries under memory pressure.
/// Thread-safe for reads from any queue.
final class ImageCacheService {
    static let shared = ImageCacheService()

    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 100          // ~100 images in memory
        c.totalCostLimit = 50 * 1024 * 1024  // 50 MB
        return c
    }()

    /// Tracks approximate cache size for debug purposes.
    private var _count = 0
    private let lock = NSLock()

    private init() {}

    // MARK: - Public API

    /// Return a cached image for the given filename, or `nil`.
    func image(for filename: String) -> UIImage? {
        cache.object(forKey: filename as NSString)
    }

    /// Store an image in the cache.
    func setImage(_ image: UIImage, for filename: String) {
        let cost = Int(image.size.width * image.size.height * 4)  // approx bytes
        cache.setObject(image, forKey: filename as NSString, cost: cost)
        lock.withLock { _count += 1 }
    }

    /// Remove a single image from the cache.
    func remove(_ filename: String) {
        cache.removeObject(forKey: filename as NSString)
        lock.withLock { _count = max(0, _count - 1) }
    }

    /// Number of images currently held in the cache.
    var cacheCount: Int {
        lock.withLock { _count }
    }

    /// Clear the entire cache (e.g. after a memory warning).
    func clear() {
        cache.removeAllObjects()
        lock.withLock { _count = 0 }
    }

    // MARK: - Async load

    /// Load an image from disk, using the cache if available.
    /// Called from any queue; result delivered on the same queue.
    func load(filename: String) async -> UIImage? {
        // 1. Check cache
        if let cached = image(for: filename) {
            return cached
        }

        // 2. Load from disk off the main thread
        let url = ImageStorageService.url(for: filename)
        let image = await Task.detached(priority: .medium) {
            UIImage(contentsOfFile: url.path)
        }.value

        // 3. Cache for next time
        if let image {
            setImage(image, for: filename)
        }
        return image
    }
}
