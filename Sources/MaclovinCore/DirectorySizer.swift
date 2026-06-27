import Foundation

/// The result of measuring a file or directory tree.
public struct SizeMeasurement: Equatable, Sendable {
    /// On-disk allocated bytes (sum of `st_blocks * 512`).
    public let bytes: UInt64
    /// Number of regular files counted (hardlinks counted once).
    public let fileCount: Int
    /// Entries that could not be read (permission gaps), tallied rather than failed.
    public let unreadableCount: Int

    public init(bytes: UInt64, fileCount: Int, unreadableCount: Int) {
        self.bytes = bytes
        self.fileCount = fileCount
        self.unreadableCount = unreadableCount
    }

    public var size: ByteSize { ByteSize(bytes) }

    /// True when every entry under the path was readable.
    public var isComplete: Bool { unreadableCount == 0 }
}

/// Measures on-disk size with Maclovin's stated methodology.
///
/// Methodology (see PRD "Sizing Methodology"):
/// - Reports **allocated on-disk bytes** (`st_blocks * 512`) — what is actually
///   reclaimed when a path is removed — not logical file length. This naturally
///   accounts for sparse files and filesystem compression.
/// - **Hardlinks** are counted once per inode within a single measurement.
/// - **Symlinks** are not followed and not traversed into.
/// - Paths that cannot be read are tallied in ``SizeMeasurement/unreadableCount``
///   rather than aborting the measurement.
///
/// Known limits: APFS **clones** may over-count (each clone reports its full
/// allocated blocks); APFS **snapshots** and **purgeable** space are not counted.
public enum DirectorySizer {
    private struct HardlinkKey: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    public static func measure(at url: URL) -> SizeMeasurement {
        measure(atPath: url.path)
    }

    public static func measure(atPath rootPath: String) -> SizeMeasurement {
        var totalBytes: UInt64 = 0
        var fileCount = 0
        var unreadableCount = 0
        var seenHardlinks: Set<HardlinkKey> = []

        func visit(_ path: String) {
            var info = stat()
            guard lstat(path, &info) == 0 else {
                unreadableCount += 1
                return
            }

            let kind = info.st_mode & S_IFMT

            // Symlinks: never followed, never counted.
            if kind == S_IFLNK {
                return
            }

            // Count a multiply-linked file's blocks only once.
            if kind == S_IFREG, info.st_nlink > 1 {
                let key = HardlinkKey(device: info.st_dev, inode: info.st_ino)
                guard seenHardlinks.insert(key).inserted else {
                    return
                }
            }

            totalBytes += UInt64(max(0, info.st_blocks)) * 512

            if kind == S_IFDIR {
                guard let children = try? FileManager.default.contentsOfDirectory(atPath: path) else {
                    unreadableCount += 1
                    return
                }
                for child in children {
                    visit(path + "/" + child)
                }
            } else if kind == S_IFREG {
                fileCount += 1
            }
        }

        visit(rootPath)
        return SizeMeasurement(bytes: totalBytes, fileCount: fileCount, unreadableCount: unreadableCount)
    }
}
