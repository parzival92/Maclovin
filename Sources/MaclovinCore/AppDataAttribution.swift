import Foundation

/// An installed application discovered from a `.app` bundle, with the identity
/// used to attribute related data back to it.
public struct InstalledApp: Equatable, Sendable {
    /// Display name (the `.app` filename without its extension).
    public let name: String
    public let path: String
    /// `CFBundleIdentifier` from the bundle's `Info.plist`, when readable.
    public let bundleID: String?

    public init(name: String, path: String, bundleID: String?) {
        self.name = name
        self.path = path
        self.bundleID = bundleID
    }
}

/// Builds the index of installed apps used for data attribution.
public enum AppIndex {
    /// Reads each `.app` bundle's `Info.plist` for its bundle identifier.
    public static func build(directories: [URL]? = nil) -> [InstalledApp] {
        let targets = directories ?? AppScanner.defaultDirectories
        var apps: [InstalledApp] = []

        for directory in targets {
            let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            guard let contents else { continue }

            for item in contents where item.pathExtension == "app" {
                apps.append(
                    InstalledApp(
                        name: item.deletingPathExtension().lastPathComponent,
                        path: item.path,
                        bundleID: bundleIdentifier(forBundleAt: item)
                    )
                )
            }
        }

        return apps
    }

    static func bundleIdentifier(forBundleAt bundle: URL) -> String? {
        let plistURL = bundle
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        guard
            let data = try? Data(contentsOf: plistURL),
            let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = object as? [String: Any],
            let identifier = dict["CFBundleIdentifier"] as? String
        else {
            return nil
        }
        return identifier
    }
}

/// The library location a piece of related app data came from.
public enum DataSource: String, Sendable, Equatable {
    case container = "Containers"
    case groupContainer = "Group Containers"
    case applicationSupport = "Application Support"
    case caches = "Caches"
}

/// A measured related-data item, attributed to an installed app or left
/// unattributed (for example, data from an app that is no longer installed).
public struct AttributedData: Equatable, Sendable {
    public let path: String
    public let folderName: String
    public let size: ByteSize
    public let source: DataSource
    public let confidence: Confidence
    /// The matched app's name, or `nil` when no installed app matched.
    public let appName: String?

    public var isAttributed: Bool { appName != nil }
}

/// Attributes related-data folders to installed apps.
///
/// Matching, strongest first:
/// - Folder name equals or contains a known **bundle identifier** → ``Confidence/high``.
///   (Bundle IDs are specific enough that a substring match — e.g. a
///   team-prefixed `TEAMID.com.acme.app` group container — is still high.)
/// - Folder name case-insensitively equals an app's **display name** → ``Confidence/medium``.
/// - Folder name shares a **reverse-DNS vendor prefix** with an installed app —
///   e.g. `com.docker.sandboxes` for `com.docker.docker` → ``Confidence/low``.
///   The broad `com.apple` prefix is excluded so system data is not piled onto
///   an Apple app.
/// - Otherwise the data is left **unattributed** (`appName == nil`).
public enum AppDataAttributor {
    /// Vendor prefixes too broad to attribute by (system data lives here).
    static let broadPrefixes: Set<String> = ["com.apple", "group.com.apple"]

    public static func attribute(
        directory: String,
        source: DataSource,
        index: [InstalledApp],
        sizer: (String) -> SizeMeasurement = { DirectorySizer.measure(atPath: $0) }
    ) -> [AttributedData] {
        let children = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        let byBundleID: [String: InstalledApp] = Dictionary(
            index.compactMap { app in app.bundleID.map { ($0.lowercased(), app) } },
            uniquingKeysWith: { first, _ in first }
        )
        let byName: [String: InstalledApp] = Dictionary(
            index.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var results: [AttributedData] = []
        for child in children where !child.hasPrefix(".") {
            let path = directory + "/" + child
            let measurement = sizer(path)
            let (app, confidence) = match(
                folderName: child,
                byBundleID: byBundleID,
                byName: byName
            )
            results.append(
                AttributedData(
                    path: path,
                    folderName: child,
                    size: measurement.size,
                    source: source,
                    confidence: confidence,
                    appName: app?.name
                )
            )
        }
        return results
    }

    static func match(
        folderName: String,
        byBundleID: [String: InstalledApp],
        byName: [String: InstalledApp]
    ) -> (InstalledApp?, Confidence) {
        let lowered = folderName.lowercased()

        if let app = byBundleID[lowered] {
            return (app, .high)
        }

        // Substring match for team-prefixed or `group.`-prefixed identifiers.
        for (bundleID, app) in byBundleID where !bundleID.isEmpty && lowered.contains(bundleID) {
            return (app, .high)
        }

        if let app = byName[lowered] {
            return (app, .medium)
        }

        // Same reverse-DNS vendor prefix (e.g. com.docker.*) → low confidence.
        if let prefix = vendorPrefix(lowered), !broadPrefixes.contains(prefix) {
            for (bundleID, app) in byBundleID where vendorPrefix(bundleID) == prefix {
                return (app, .low)
            }
        }

        return (nil, .low)
    }

    /// The first two reverse-DNS components of an identifier (e.g. `com.docker`),
    /// or `nil` when the name is not a dotted identifier with a subdomain.
    static func vendorPrefix(_ identifier: String) -> String? {
        let parts = identifier.split(separator: ".")
        guard parts.count >= 3 else { return nil }
        return parts.prefix(2).joined(separator: ".")
    }
}
