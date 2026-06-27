import Foundation

/// One app's total on-disk footprint: its bundle plus attributed related data.
public struct AppFootprint: Equatable, Sendable {
    public let name: String
    public let bundleBytes: UInt64
    public let dataBytes: UInt64
    /// Lowest confidence among the data attributed to this app (the bundle
    /// itself is always high).
    public let dataConfidence: Confidence?

    public var totalBytes: UInt64 { bundleBytes + dataBytes }
    public var totalSize: ByteSize { ByteSize(totalBytes) }
    public var bundleSize: ByteSize { ByteSize(bundleBytes) }
    public var dataSize: ByteSize { ByteSize(dataBytes) }
}

/// A summed bucket of related data that matched no installed app.
public struct UnattributedBucket: Equatable, Sendable {
    public let source: DataSource
    public let bytes: UInt64
    /// Largest unattributed folders within the source, for context.
    public let largest: [AttributedData]

    public var size: ByteSize { ByteSize(bytes) }
}

/// The full applications audit: per-app footprints plus unattributed data.
public struct AppsAuditReport: Equatable, Sendable {
    public let footprints: [AppFootprint]
    public let unattributed: [UnattributedBucket]
    public let scannedDirectories: [String]
    public let skippedDirectories: [String]

    public var attributedBytes: UInt64 { footprints.reduce(0) { $0 + $1.totalBytes } }
    public var unattributedBytes: UInt64 { unattributed.reduce(0) { $0 + $1.bytes } }
    public var totalBytes: UInt64 { attributedBytes + unattributedBytes }
}

/// Produces an applications audit: bundle sizes plus related-data attribution
/// across Containers, Group Containers, Application Support, and Caches.
public enum AppsAuditor {
    /// The related-data directories scanned, paired with their source label.
    public static var defaultDataDirectories: [(String, DataSource)] {
        let library = MaclovinPaths.homeDirectory.appendingPathComponent("Library", isDirectory: true)
        return [
            (library.appendingPathComponent("Containers").path, .container),
            (library.appendingPathComponent("Group Containers").path, .groupContainer),
            (library.appendingPathComponent("Application Support").path, .applicationSupport),
            (library.appendingPathComponent("Caches").path, .caches)
        ]
    }

    public static func audit(
        appDirectories: [URL]? = nil,
        dataDirectories: [(String, DataSource)]? = nil,
        sizer: (String) -> SizeMeasurement = { DirectorySizer.measure(atPath: $0) }
    ) -> AppsAuditReport {
        let scan = AppScanner.scan(directories: appDirectories, sizer: sizer)
        let index = AppIndex.build(directories: appDirectories)

        var dataBytesByApp: [String: UInt64] = [:]
        var dataConfidenceByApp: [String: Confidence] = [:]
        var unattributedBySource: [DataSource: [AttributedData]] = [:]

        for (directory, source) in dataDirectories ?? defaultDataDirectories {
            for item in AppDataAttributor.attribute(directory: directory, source: source, index: index, sizer: sizer) {
                if let app = item.appName {
                    dataBytesByApp[app, default: 0] += item.size.bytes
                    dataConfidenceByApp[app] = weakest(dataConfidenceByApp[app], item.confidence)
                } else {
                    unattributedBySource[source, default: []].append(item)
                }
            }
        }

        var footprints: [AppFootprint] = scan.entries.map { entry in
            AppFootprint(
                name: entry.name,
                bundleBytes: entry.size.bytes,
                dataBytes: dataBytesByApp[entry.name] ?? 0,
                dataConfidence: dataConfidenceByApp[entry.name]
            )
        }
        footprints.sort { $0.totalBytes > $1.totalBytes }

        let buckets = unattributedBySource
            .map { source, items in
                UnattributedBucket(
                    source: source,
                    bytes: items.reduce(0) { $0 + $1.size.bytes },
                    largest: items.sorted { $0.size > $1.size }.prefix(5).map { $0 }
                )
            }
            .sorted { $0.bytes > $1.bytes }

        return AppsAuditReport(
            footprints: footprints,
            unattributed: buckets,
            scannedDirectories: scan.scannedDirectories,
            skippedDirectories: scan.skippedDirectories
        )
    }

    /// Returns the lower-confidence of two values (the bundle is always high, so
    /// a footprint's data confidence reflects its weakest attribution).
    static func weakest(_ current: Confidence?, _ next: Confidence) -> Confidence {
        let rank: (Confidence) -> Int = { switch $0 { case .high: 0; case .medium: 1; case .low: 2 } }
        guard let current else { return next }
        return rank(next) > rank(current) ? next : current
    }
}
