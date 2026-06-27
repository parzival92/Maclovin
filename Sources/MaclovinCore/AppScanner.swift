import Foundation

/// A single application bundle and its measured on-disk size.
public struct AppEntry: Equatable, Sendable {
    /// Display name (the `.app` filename without its extension).
    public let name: String
    public let path: String
    public let size: ByteSize
    /// Attribution confidence. A `.app` bundle is always ``Confidence/high``.
    public let confidence: Confidence
    /// False when some files under the bundle could not be read.
    public let isComplete: Bool

    public init(name: String, path: String, size: ByteSize, confidence: Confidence, isComplete: Bool) {
        self.name = name
        self.path = path
        self.size = size
        self.confidence = confidence
        self.isComplete = isComplete
    }
}

/// The outcome of scanning the application directories.
public struct AppScanResult: Equatable, Sendable {
    /// App bundles, sorted largest first.
    public let entries: [AppEntry]
    public let totalBytes: UInt64
    public let scannedDirectories: [String]
    /// Directories that were absent or unreadable.
    public let skippedDirectories: [String]

    public var totalSize: ByteSize { ByteSize(totalBytes) }
}

/// Scans the application directories for `.app` bundles and measures each.
///
/// V1 measures bundles directly (always high confidence). Attribution of
/// related application support, container, and developer-tool data is layered
/// on separately.
public enum AppScanner {
    /// The directories scanned by default: `/Applications` and `~/Applications`.
    public static var defaultDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            MaclovinPaths.homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    /// Path-based entry point. Convenient for callers and tests that work in
    /// `String` paths rather than `URL`.
    public static func scan(
        directoryPaths: [String],
        sizer: (String) -> SizeMeasurement = { DirectorySizer.measure(atPath: $0) }
    ) -> AppScanResult {
        scan(
            directories: directoryPaths.map { URL(fileURLWithPath: $0, isDirectory: true) },
            sizer: sizer
        )
    }

    /// - Parameters:
    ///   - directories: Locations to scan for `.app` bundles. Defaults to
    ///     ``defaultDirectories``.
    ///   - sizer: Size measurement function (receives a bundle path), injectable
    ///     for testing. Defaults to ``DirectorySizer/measure(atPath:)``.
    public static func scan(
        directories: [URL]? = nil,
        sizer: (String) -> SizeMeasurement = { DirectorySizer.measure(atPath: $0) }
    ) -> AppScanResult {
        let targets = directories ?? defaultDirectories
        var entries: [AppEntry] = []
        var scanned: [String] = []
        var skipped: [String] = []

        for directory in targets {
            let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            guard let contents else {
                skipped.append(directory.path)
                continue
            }

            scanned.append(directory.path)

            for item in contents where item.pathExtension == "app" {
                let measurement = sizer(item.path)
                entries.append(
                    AppEntry(
                        name: item.deletingPathExtension().lastPathComponent,
                        path: item.path,
                        size: measurement.size,
                        confidence: .high,
                        isComplete: measurement.isComplete
                    )
                )
            }
        }

        entries.sort { $0.size > $1.size }
        let totalBytes = entries.reduce(UInt64(0)) { $0 + $1.size.bytes }

        return AppScanResult(
            entries: entries,
            totalBytes: totalBytes,
            scannedDirectories: scanned,
            skippedDirectories: skipped
        )
    }
}
