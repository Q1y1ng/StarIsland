import Foundation
import Compression

// MARK: - Zip Helper

/// Minimal ZIP archive creation and extraction using only Foundation.
///
/// ## Supported methods
/// - **Stored** (no compression) — used for creation.
/// - **Deflated** — supported during extraction for compatibility with
///   archives created by other tools (macOS Finder, Info-Zip, etc.).
///
/// ## Notes
/// - File names are stored as UTF‑8.
/// - Creation uses the "stored" method because almost all backup content
///   (JSON text and JPEG images) benefits little from re‑compression.
enum ZipHelper {

    // MARK: - Create

    /// Create a ZIP archive containing every file under `sourceDirectory`.
    /// - Parameter sourceDirectory: A directory whose contents will be added.
    /// - Parameter destination: The output ZIP file URL.
    static func createZip(from sourceDirectory: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceDirectory.path) else {
            throw ZipError.sourceNotFound
        }

        let entries = try collectEntries(in: sourceDirectory)
        var centralDirectory = Data()
        var localData = Data()
        var offset: UInt32 = 0

        for entry in entries.sorted(by: { $0.name < $1.name }) {
            let crc = crc32(entry.data)
            let nameData = Data(entry.name.utf8)

            // ── Local file header ───────────────────────────────────
            var lh = Data()
            lh.append(UInt32(0x04034b50).littleEndian)   // signature
            lh.append(UInt16(20).littleEndian)            // version needed (2.0)
            lh.append(UInt16(0).littleEndian)              // flags
            lh.append(UInt16(0).littleEndian)              // method: stored
            lh.append(UInt16(0xAC34).littleEndian)        // mod time (~12:34)
            lh.append(UInt16(0x4A21).littleEndian)        // mod date (~2026‑06‑24)
            lh.append(crc.littleEndian)
            lh.append(UInt32(entry.data.count).littleEndian)
            lh.append(UInt32(entry.data.count).littleEndian)
            lh.append(UInt16(nameData.count).littleEndian)
            lh.append(UInt16(0).littleEndian)
            lh.append(nameData)

            localData.append(lh)
            localData.append(entry.data)

            // ── Central directory entry ─────────────────────────────
            var ce = Data()
            ce.append(UInt32(0x02014b50).littleEndian)     // signature
            ce.append(UInt16(20).littleEndian)              // version made by
            ce.append(UInt16(20).littleEndian)              // version needed
            ce.append(UInt16(0).littleEndian)               // flags
            ce.append(UInt16(0).littleEndian)               // method: stored
            ce.append(UInt16(0xAC34).littleEndian)          // mod time
            ce.append(UInt16(0x4A21).littleEndian)          // mod date
            ce.append(crc.littleEndian)
            ce.append(UInt32(entry.data.count).littleEndian)
            ce.append(UInt32(entry.data.count).littleEndian)
            ce.append(UInt16(nameData.count).littleEndian)
            ce.append(UInt16(0).littleEndian)               // extra field length
            ce.append(UInt16(0).littleEndian)               // file comment length
            ce.append(UInt16(0).littleEndian)               // disk number
            ce.append(UInt16(0).littleEndian)               // internal attributes
            ce.append(UInt32(0).littleEndian)               // external attributes
            ce.append(offset.littleEndian)                  // offset of local header
            ce.append(nameData)

            centralDirectory.append(ce)
            offset += UInt32(lh.count + entry.data.count)
        }

        // ── End of central directory ────────────────────────────────
        var eocd = Data()
        let centralOffset = UInt32(localData.count)
        eocd.append(UInt32(0x06054b50).littleEndian)      // signature
        eocd.append(UInt16(0).littleEndian)                // disk #
        eocd.append(UInt16(0).littleEndian)                // disk # with CD
        eocd.append(UInt16(entries.count).littleEndian)    // entries on disk
        eocd.append(UInt16(entries.count).littleEndian)    // total entries
        eocd.append(UInt32(centralDirectory.count).littleEndian)
        eocd.append(centralOffset.littleEndian)
        eocd.append(UInt16(0).littleEndian)                // comment length

        var zip = Data()
        zip.append(localData)
        zip.append(centralDirectory)
        zip.append(eocd)

        try zip.write(to: destination, options: .atomic)
    }

    // MARK: - Extract

    /// Extract a ZIP archive into `destinationDirectory`.
    static func extractZip(from source: URL, to destination: URL) throws {
        let data = try Data(contentsOf: source)
        let fm = FileManager.default

        guard data.count >= 22 else { throw ZipError.invalidArchive }

        // Locate End of Central Directory record
        let eocd = try locateEOCD(in: data)
        let entryCount = Int(eocd.read(UInt16.self, at: 8))
        let cdSize = eocd.read(UInt32.self, at: 12)
        let cdOffset = eocd.read(UInt32.self, at: 16)

        guard cdOffset + cdSize <= UInt32(data.count) else {
            throw ZipError.invalidArchive
        }

        // Parse central directory entries
        var entries: [CentralDirEntry] = []
        var pos = Int(cdOffset)
        for _ in 0 ..< entryCount {
            guard pos + 46 <= data.count else { throw ZipError.invalidArchive }
            let sig = data.read(UInt32.self, at: pos)
            guard sig == 0x02014b50 else { throw ZipError.invalidArchive }

            let method    = data.read(UInt16.self, at: pos + 10)
            let crc       = data.read(UInt32.self, at: pos + 16)
            let compSize  = data.read(UInt32.self, at: pos + 20)
            let unCompSize = data.read(UInt32.self, at: pos + 24)
            let nameLen   = Int(data.read(UInt16.self, at: pos + 28))
            let extraLen  = Int(data.read(UInt16.self, at: pos + 30))
            let commentLen = Int(data.read(UInt16.self, at: pos + 32))
            let localOffset = data.read(UInt32.self, at: pos + 42)

            guard pos + 46 + nameLen + extraLen + commentLen <= data.count else {
                throw ZipError.invalidArchive
            }

            let nameSlice = data[pos + 46 ..< pos + 46 + nameLen]
            guard let name = String(data: nameSlice, encoding: .utf8) else {
                throw ZipError.invalidArchive
            }

            entries.append(CentralDirEntry(
                name: name,
                method: method,
                crc: crc,
                compressedSize: compSize,
                uncompressedSize: unCompSize,
                localHeaderOffset: Int(localOffset)
            ))

            pos += 46 + nameLen + extraLen + commentLen
        }

        // Extract each entry
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        for entry in entries {
            // Skip directory entries (trailing /)
            guard !entry.name.hasSuffix("/") else {
                let dirURL = destination.appendingPathComponent(entry.name)
                try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
                continue
            }

            // Parse local file header to find data
            let localPos = entry.localHeaderOffset
            guard localPos + 30 <= data.count else { throw ZipError.invalidArchive }
            let localSig = data.read(UInt32.self, at: localPos)
            guard localSig == 0x04034b50 else { throw ZipError.invalidArchive }

            let localNameLen = Int(data.read(UInt16.self, at: localPos + 26))
            let localExtraLen = Int(data.read(UInt16.self, at: localPos + 28))
            let dataStart = localPos + 30 + localNameLen + localExtraLen

            guard dataStart + Int(entry.compressedSize) <= data.count else {
                throw ZipError.invalidArchive
            }

            let raw = data[dataStart ..< dataStart + Int(entry.compressedSize)]

            let fileData: Data
            if entry.method == 0 {
                // Stored
                fileData = raw
            } else if entry.method == 8 {
                // Deflated – use Compression framework
                guard let inflated = raw.inflate() else {
                    throw ZipError.compressionFailed
                }
                fileData = inflated
            } else {
                throw ZipError.unsupportedMethod(entry.method)
            }

            let fileURL = destination.appendingPathComponent(entry.name)
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try fileData.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Types

    private struct DirEntry {
        let name: String
        let data: Data
    }

    private struct CentralDirEntry {
        let name: String
        let method: UInt16
        let crc: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: Int
    }

    // MARK: - Helpers

    private static func collectEntries(in directory: URL) throws -> [DirEntry] {
        let fm = FileManager.default
        let enumerator = fm.enumerator(at: directory,
                                       includingPropertiesForKeys: [.isDirectoryKey],
                                       options: [.skipsHiddenFiles])
        guard let enumerator else { throw ZipError.sourceNotFound }

        var entries: [DirEntry] = []
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true { continue }

            let relativePath = fileURL.path
                .replacingOccurrences(of: directory.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            guard !relativePath.isEmpty else { continue }
            let data = try Data(contentsOf: fileURL)
            entries.append(DirEntry(name: relativePath, data: data))
        }
        return entries
    }

    private static func locateEOCD(in data: Data) throws -> Data {
        // EOCD signature is at most 65557 bytes from the end (max comment = 65535)
        let searchStart = max(0, data.count - 65557)
        for i in (searchStart ..< data.count - 3).reversed() {
            if data.read(UInt32.self, at: i) == 0x06054b50 {
                return Data(data[i...])
            }
        }
        throw ZipError.invalidArchive
    }

    // MARK: - CRC-32 (pure Swift)

    private static func crc32(_ data: Data) -> UInt32 {
        var table: [UInt32] = Array(repeating: 0, count: 256)
        for i in 0 ..< 256 {
            var crc = UInt32(i)
            for _ in 0 ..< 8 {
                crc = (crc & 1) != 0 ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1)
            }
            table[i] = crc
        }
        var result: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let idx = Int((result ^ UInt32(byte)) & 0xFF)
            result = table[idx] ^ (result >> 8)
        }
        return result ^ 0xFFFF_FFFF
    }
}

// MARK: - Errors

enum ZipError: LocalizedError {
    case sourceNotFound
    case invalidArchive
    case compressionFailed
    case unsupportedMethod(UInt16)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            return "备份源文件不存在"
        case .invalidArchive:
            return "无效的备份文件"
        case .compressionFailed:
            return "数据解压失败"
        case .unsupportedMethod(let m):
            return "不支持的压缩方式: \(m)"
        }
    }
}

// MARK: - Data helpers

private extension Data {
    func read<T: FixedWidthInteger>(_: T.Type, at offset: Int) -> T {
        return withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: T.self)
        }
    }
}

// MARK: - Raw deflate via Compression framework



// MARK: - Raw deflate via Compression framework

private extension Data {

    /// Inflate (decompress) raw deflate data using the Compression framework.
    /// ZIP method 8 uses **raw** deflate (no zlib header), so we pass
    /// `COMPRESSION_DEFLATE` rather than `COMPRESSION_ZLIB`.
    func inflate() -> Data? {
        let source = self
        var output = Data(count: max(source.count * 4, 4096))
        var stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }

        var status = compression_stream_init(stream,
                                              COMPRESSION_STREAM_DECODE,
                                              COMPRESSION_DEFLATE)
        guard status != COMPRESSION_STATUS_ERROR else { return nil }

        defer { compression_stream_destroy(stream) }

        return source.withUnsafeBytes { srcPtr in
            let srcBase = srcPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            var result = Data()

            stream.pointee.src_ptr  = srcBase
            stream.pointee.src_size = source.count

            repeat {
                let dstSize = output.count
                status = output.withUnsafeMutableBytes { dstPtr in
                    let dstBase = dstPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    stream.pointee.dst_ptr  = dstBase
                    stream.pointee.dst_size = dstSize
                    return compression_stream_process(stream, 0)
                }

                let produced = dstSize - stream.pointee.dst_size
                guard produced > 0 else { break }
                result.append(output[0 ..< produced])

                if status == COMPRESSION_STATUS_END {
                    break
                }
                if status == COMPRESSION_STATUS_ERROR {
                    return nil
                }

                output.count *= 2
            } while status == COMPRESSION_STATUS_OK

            return result
        }
    }
}
