import Foundation

/// The outcome of resolving a user-supplied `<app-name>` to an installed app.
public enum AppResolution: Equatable, Sendable {
    /// Exactly one bundle matched the query.
    case resolved(InstalledApp)
    /// No installed bundle matched the query.
    case notFound(query: String)
    /// More than one distinct bundle matched the query. Candidates are sorted by
    /// path so the report is stable, and the user must re-run with something more
    /// specific (a bundle identifier or a name that picks one out).
    case ambiguous(query: String, candidates: [InstalledApp])
}

/// Maps a user string from `maclovin apps uninstall <app-name>` to a single
/// installed `.app` bundle.
///
/// Resolution rules:
/// - A query matches against an app's **display name** (the `.app` filename
///   without its extension) or its **bundle identifier** (`CFBundleIdentifier`).
/// - Matching is **case-insensitive**: `slack` resolves `Slack.app`.
/// - The trailing **`.app` suffix is optional**: `Slack`, `slack`, and
///   `Slack.app` all resolve the same bundle. (Bundle identifiers never carry a
///   `.app` suffix, so it is only stripped for the name comparison.)
/// - Bundle-identifier matches take precedence over display-name matches, so a
///   user who types a specific identifier always targets that exact app.
/// - A query is **ambiguous** when it matches more than one distinct bundle —
///   for example a `Slack.app` present in both `/Applications` and
///   `~/Applications`. All candidates are returned for the caller to report.
public enum AppResolver {
    /// Resolves a query against the apps discovered in `directories`
    /// (defaults to `/Applications` and `~/Applications`).
    public static func resolve(_ query: String, directories: [URL]? = nil) -> AppResolution {
        resolve(query, in: AppIndex.build(directories: directories))
    }

    /// Resolves a query against a pre-built index of installed apps. Pure and
    /// synchronous so it can be unit-tested without touching the filesystem.
    public static func resolve(_ query: String, in apps: [InstalledApp]) -> AppResolution {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredQuery = trimmed.lowercased()
        let loweredName = stripAppSuffix(trimmed).lowercased()

        // Tier 1: exact bundle-identifier match (most specific).
        let byBundleID = apps.filter { $0.bundleID?.lowercased() == loweredQuery }
        if !byBundleID.isEmpty {
            return finalize(query: trimmed, matches: byBundleID)
        }

        // Tier 2: display-name / `.app`-filename match.
        let byName = apps.filter { $0.name.lowercased() == loweredName }
        if !byName.isEmpty {
            return finalize(query: trimmed, matches: byName)
        }

        return .notFound(query: trimmed)
    }

    /// Collapses matches that point at the same bundle path and classifies the
    /// result as resolved or ambiguous.
    static func finalize(query: String, matches: [InstalledApp]) -> AppResolution {
        var seen: Set<String> = []
        let distinct = matches
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.path < $1.path }

        if distinct.count == 1 {
            return .resolved(distinct[0])
        }
        return .ambiguous(query: query, candidates: distinct)
    }

    /// Removes a single trailing `.app` extension, case-insensitively, leaving
    /// other input untouched.
    static func stripAppSuffix(_ value: String) -> String {
        guard value.lowercased().hasSuffix(".app") else { return value }
        return String(value.dropLast(4))
    }
}
