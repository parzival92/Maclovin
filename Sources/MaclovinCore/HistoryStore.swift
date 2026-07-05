import Foundation

/// One recorded action or scan, persisted as a single JSON file under
/// `~/.local/state/maclovin/history/`.
///
/// History stores summaries and action logs only — never full private file
/// inventories (see PRD "Local-Only Data").
public struct HistoryEntry: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case scan
        case cleanupApply = "cleanup-apply"
        case appUninstall = "app-uninstall"
        case brewUninstall = "brew-uninstall"

        public var label: String {
            switch self {
            case .scan: "Scan"
            case .cleanupApply: "Cleanup Apply"
            case .appUninstall: "App Uninstall"
            case .brewUninstall: "Homebrew Uninstall"
            }
        }
    }

    /// Per-candidate estimated-vs-freed record for cleanup batches, stored on
    /// the same basis it was measured (see CleanupReconciliation).
    public struct CandidateRecord: Codable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let mode: String
        public let status: String
        public let estimatedBytes: UInt64
        public let freedBytes: UInt64
        public let note: String?

        public init(_ reconciliation: CandidateReconciliation) {
            id = reconciliation.candidateID
            title = reconciliation.title
            mode = reconciliation.mode.rawValue
            status = reconciliation.status.rawValue
            estimatedBytes = reconciliation.estimatedBytes
            freedBytes = reconciliation.freedBytes
            note = reconciliation.outcome.note
        }

        /// Rebuilds the reconciliation pair for rendering `history show`.
        public var reconciliation: CandidateReconciliation {
            CandidateReconciliation(
                estimate: CleanupEstimate(
                    candidateID: id,
                    title: title,
                    mode: CleanupMode(rawValue: mode) ?? .directDelete,
                    estimatedBytes: estimatedBytes
                ),
                outcome: CleanupOutcome(
                    candidateID: id,
                    status: CleanupStatus(rawValue: status) ?? .skipped,
                    freedBytes: freedBytes,
                    note: note
                )
            )
        }
    }

    public var timestamp: Date
    public var kind: Kind
    public var macOSVersion: String
    /// Short human-readable facts: disk usage summary, top contributors,
    /// the uninstall target, and similar headline rows.
    public var summary: [String]
    /// Cleanup batches: the per-candidate estimate-vs-freed reconciliation.
    public var candidates: [CandidateRecord]
    /// Errors and skipped paths, stated plainly.
    public var errors: [String]

    public init(
        timestamp: Date = Date(),
        kind: Kind,
        macOSVersion: String = HistoryStore.currentMacOSVersion(),
        summary: [String],
        candidates: [CandidateRecord] = [],
        errors: [String] = []
    ) {
        self.timestamp = timestamp
        self.kind = kind
        self.macOSVersion = macOSVersion
        self.summary = summary
        self.candidates = candidates
        self.errors = errors
    }

    /// The one-line headline shown in the `maclovin history` list.
    public var headline: String {
        summary.first ?? kind.label
    }
}

/// Reads and writes history entries as individual JSON files.
public struct HistoryStore: Sendable {
    public let directory: URL

    /// The default store under `~/.local/state/maclovin/history`.
    public static var `default`: HistoryStore {
        HistoryStore(directory: MaclovinPaths.historyDirectory.appendingPathComponent("history", isDirectory: true))
    }

    public init(directory: URL) {
        self.directory = directory
    }

    /// A stable, sortable identifier derived from the timestamp and kind, used
    /// as the file basename and accepted by `history show <id>`.
    public static func entryID(for entry: HistoryEntry) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter.string(from: entry.timestamp) + "-" + entry.kind.rawValue
    }

    public static func currentMacOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// Appends an entry. Failures are returned as a thrown error; callers
    /// treat history problems as warnings, never as reasons to abort an action
    /// that already happened.
    @discardableResult
    public func append(_ entry: HistoryEntry) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = Self.entryID(for: entry)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        try data.write(to: directory.appendingPathComponent(id + ".json"), options: .atomic)
        return id
    }

    /// All entries, newest first, paired with their IDs. Unreadable files are
    /// skipped rather than failing the listing.
    public func list() -> [(id: String, entry: HistoryEntry)] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { file -> (String, HistoryEntry)? in
                guard
                    let data = try? Data(contentsOf: file),
                    let entry = try? decoder.decode(HistoryEntry.self, from: data)
                else {
                    return nil
                }
                return (file.deletingPathExtension().lastPathComponent, entry)
            }
            .sorted { $0.1.timestamp > $1.1.timestamp }
    }

    /// The most recent entry, if any.
    public func latest() -> (id: String, entry: HistoryEntry)? {
        list().first
    }

    /// Looks an entry up by the ID shown in the list.
    public func entry(id: String) -> HistoryEntry? {
        list().first { $0.id == id }?.entry
    }
}
