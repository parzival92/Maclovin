import Foundation

/// What `cleanup apply` would do to reclaim a candidate's space. The action
/// determines the ``CleanupMode`` and therefore how the estimate and the
/// freed bytes are measured (see CleanupReconciliation).
public enum CleanupAction: Equatable, Sendable {
    /// Delegate to an official tool command, e.g. `brew cleanup`.
    case command(tool: String, arguments: [String])
    /// Remove well-known generated/cache paths directly.
    case deletePaths([String])

    public var mode: CleanupMode {
        switch self {
        case .command: .officialCommand
        case .deletePaths: .directDelete
        }
    }

    /// One-line rendering for reports: the command line or the paths.
    public var displayed: String {
        switch self {
        case .command(let tool, let arguments):
            ([tool] + arguments).joined(separator: " ")
        case .deletePaths(let paths):
            paths.joined(separator: ", ")
        }
    }
}

/// One cleanup opportunity found by `cleanup scan` (field contract per
/// implementation plan Milestone 6). Scanning never changes files; candidates
/// only describe what `cleanup apply` could do after review and confirmation.
public struct CleanupCandidate: Equatable, Sendable {
    public let id: String
    public let title: String
    /// Group heading used by `cleanup review`: "Homebrew", "npm", "Xcode", …
    public let source: String
    public let action: CleanupAction
    public let estimatedBytes: UInt64
    /// Where this specific estimate came from, stated per candidate so
    /// estimate and freed bytes reconcile on the same basis (issue #5).
    public let estimateBasis: String
    public let risk: Risk
    public let confidence: Confidence
    public let explanation: String
    /// For official-command candidates: the tool's managed store, measured
    /// before and after the command so freed bytes reconcile per the
    /// official-command contract. Nil for direct deletes (the action's paths
    /// are the measurement target) and when the store is unknown.
    public let storePath: String?

    public init(
        id: String,
        title: String,
        source: String,
        action: CleanupAction,
        estimatedBytes: UInt64,
        estimateBasis: String,
        risk: Risk,
        confidence: Confidence,
        explanation: String,
        storePath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.action = action
        self.estimatedBytes = estimatedBytes
        self.estimateBasis = estimateBasis
        self.risk = risk
        self.confidence = confidence
        self.explanation = explanation
        self.storePath = storePath
    }

    public var mode: CleanupMode { action.mode }
    public var estimatedSize: ByteSize { ByteSize(estimatedBytes) }

    /// The estimate side of the apply-time reconciliation.
    public var estimate: CleanupEstimate {
        CleanupEstimate(candidateID: id, title: title, mode: mode, estimatedBytes: estimatedBytes)
    }
}

/// A storage finding Maclovin reports but never offers to clean
/// (PRD "Audit-Only Targets"): Docker data and language version managers.
public struct AuditOnlyFinding: Equatable, Sendable {
    public let title: String
    public let path: String
    public let bytes: UInt64
    public let note: String

    public init(title: String, path: String, bytes: UInt64, note: String) {
        self.title = title
        self.path = path
        self.bytes = bytes
        self.note = note
    }

    public var size: ByteSize { ByteSize(bytes) }
}

public struct CleanupScanResult: Equatable, Sendable {
    /// Candidates sorted largest estimate first.
    public let candidates: [CleanupCandidate]
    /// Audit-only findings sorted largest first.
    public let auditOnly: [AuditOnlyFinding]
    /// Paths dropped because `[scan] exclude_paths` covers them.
    public let excluded: [String]

    public init(candidates: [CleanupCandidate], auditOnly: [AuditOnlyFinding], excluded: [String]) {
        self.candidates = candidates
        self.auditOnly = auditOnly
        self.excluded = excluded
    }

    /// Sum of candidate estimates. An upper bound: official commands decide
    /// what they actually remove, so some stores may free less.
    public var totalEstimatedBytes: UInt64 {
        candidates.reduce(0) { $0 + $1.estimatedBytes }
    }

    public var totalEstimatedSize: ByteSize { ByteSize(totalEstimatedBytes) }
}

/// Finds cleanup candidates within the PRD "Cleanup Boundary" without writing
/// anything. Official tool commands are preferred over direct deletion;
/// direct deletion is limited to well-known generated/cache paths.
public struct CleanupScanner: Sendable {
    /// Everything the scanner touches, injectable for tests: the home
    /// directory, the config, tool probing, and tree measurement.
    public struct Environment: Sendable {
        public var home: String
        public var config: ConfigFile
        /// Runs a read-only probe of a local tool, returning trimmed stdout on
        /// success or nil when the tool is missing or fails (see Shell.output).
        public var toolOutput: @Sendable (_ tool: String, _ arguments: [String]) -> String?
        public var measure: @Sendable (_ path: String) -> SizeMeasurement

        public init(
            home: String,
            config: ConfigFile,
            toolOutput: @escaping @Sendable (String, [String]) -> String?,
            measure: @escaping @Sendable (String) -> SizeMeasurement = { DirectorySizer.measure(atPath: $0) }
        ) {
            self.home = home
            self.config = config
            self.toolOutput = toolOutput
            self.measure = measure
        }

        public static func live(config: ConfigFile = .load()) -> Environment {
            Environment(
                home: MaclovinPaths.homeDirectory.path,
                config: config,
                toolOutput: { Shell.output($0, $1) },
                measure: { DirectorySizer.measure(atPath: $0) }
            )
        }
    }

    let environment: Environment

    public init(environment: Environment) {
        self.environment = environment
    }

    public func scan() -> CleanupScanResult {
        var excluded: [String] = []

        var candidates: [CleanupCandidate] = []
        candidates.append(contentsOf: [
            brewCleanupCandidate(),
            npmCacheCandidate(excluded: &excluded),
            yarnCacheCandidate(excluded: &excluded),
            pnpmStoreCandidate(excluded: &excluded),
            pipCacheCandidate(excluded: &excluded),
            unavailableSimulatorsCandidate()
        ].compactMap { $0 })

        candidates.append(contentsOf: directDeleteCandidates(excluded: &excluded))

        return CleanupScanResult(
            candidates: candidates.sorted { $0.estimatedBytes > $1.estimatedBytes },
            auditOnly: auditOnlyFindings(excluded: &excluded),
            excluded: excluded
        )
    }

    // MARK: - Official-command candidates

    /// `brew cleanup`: the one source with a true dry-run, so the estimate is
    /// parsed from the tool's own output per the official-command contract.
    func brewCleanupCandidate() -> CleanupCandidate? {
        guard let dryRun = environment.toolOutput("brew", ["cleanup", "--dry-run"]) else {
            return nil
        }
        let parsed = Self.parseBrewDryRun(dryRun)
        guard parsed.itemCount > 0 || parsed.bytes > 0 else { return nil }

        return CleanupCandidate(
            id: "brew-cleanup",
            title: "Homebrew cleanup",
            source: "Homebrew",
            action: .command(tool: "brew", arguments: ["cleanup"]),
            estimatedBytes: parsed.bytes,
            estimateBasis: "parsed from `brew cleanup --dry-run` (\(parsed.itemCount) items)",
            risk: .low,
            confidence: .high,
            explanation: "Outdated downloads and stale versions Homebrew itself says it would remove.",
            storePath: environment.toolOutput("brew", ["--cache"])
        )
    }

    /// npm, yarn, and pip caches are removed whole by their official clean
    /// commands, so the store's measured size is the estimate.
    func npmCacheCandidate(excluded: inout [String]) -> CleanupCandidate? {
        guard let cacheRoot = environment.toolOutput("npm", ["config", "get", "cache"]) else {
            return nil
        }
        return storeCandidate(
            id: "npm-cache",
            title: "npm cache",
            source: "npm",
            storePath: cacheRoot + "/_cacache",
            command: ("npm", ["cache", "clean", "--force"]),
            basis: "on-disk size of the npm cache store; `npm cache clean --force` removes it whole",
            confidence: .high,
            explanation: "Downloaded package tarballs and metadata; npm re-fetches on demand.",
            excluded: &excluded
        )
    }

    func yarnCacheCandidate(excluded: inout [String]) -> CleanupCandidate? {
        guard let cacheDir = environment.toolOutput("yarn", ["cache", "dir"]) else {
            return nil
        }
        return storeCandidate(
            id: "yarn-cache",
            title: "yarn cache",
            source: "yarn",
            storePath: cacheDir,
            command: ("yarn", ["cache", "clean"]),
            basis: "on-disk size of the yarn cache directory; `yarn cache clean` removes it whole",
            confidence: .high,
            explanation: "Cached packages; yarn re-fetches on demand.",
            excluded: &excluded
        )
    }

    /// `pnpm store prune` removes only packages no project references, so the
    /// store size is an upper bound — stated, not faked (issue #5).
    func pnpmStoreCandidate(excluded: inout [String]) -> CleanupCandidate? {
        guard let storePath = environment.toolOutput("pnpm", ["store", "path"]) else {
            return nil
        }
        return storeCandidate(
            id: "pnpm-store",
            title: "pnpm store prune",
            source: "pnpm",
            storePath: storePath,
            command: ("pnpm", ["store", "prune"]),
            basis: "on-disk size of the whole pnpm store; prune removes only unreferenced packages, so actual freed space may be much less",
            confidence: .medium,
            explanation: "Packages no project references any more; pnpm decides which those are.",
            excluded: &excluded
        )
    }

    func pipCacheCandidate(excluded: inout [String]) -> CleanupCandidate? {
        guard let cacheDir = environment.toolOutput("pip3", ["cache", "dir"]) else {
            return nil
        }
        return storeCandidate(
            id: "pip-cache",
            title: "pip cache",
            source: "pip",
            storePath: cacheDir,
            command: ("pip3", ["cache", "purge"]),
            basis: "on-disk size of the pip cache directory; `pip3 cache purge` removes it whole",
            confidence: .high,
            explanation: "Cached wheels and HTTP downloads; pip re-fetches on demand.",
            excluded: &excluded
        )
    }

    /// `xcrun simctl delete unavailable`: simctl reports no sizes, so the
    /// estimate is honestly zero and freed space is measured at apply time as
    /// the before/after delta of the CoreSimulator devices directory.
    func unavailableSimulatorsCandidate() -> CleanupCandidate? {
        guard let listing = environment.toolOutput("xcrun", ["simctl", "list", "devices", "unavailable"]) else {
            return nil
        }
        let deviceCount = listing
            .split(separator: "\n")
            .filter { $0.contains("(unavailable") }
            .count
        guard deviceCount > 0 else { return nil }

        return CleanupCandidate(
            id: "simctl-unavailable",
            title: "Unavailable iOS Simulator devices (\(deviceCount))",
            source: "Xcode",
            action: .command(tool: "xcrun", arguments: ["simctl", "delete", "unavailable"]),
            estimatedBytes: 0,
            estimateBasis: "simctl does not report sizes; freed space is measured as the before/after delta of ~/Library/Developer/CoreSimulator/Devices",
            risk: .low,
            confidence: .low,
            explanation: "Simulator devices whose runtime is no longer installed; simctl decides which qualify.",
            storePath: environment.home + "/Library/Developer/CoreSimulator/Devices"
        )
    }

    /// Shared shape for official commands that clean a measurable store.
    private func storeCandidate(
        id: String,
        title: String,
        source: String,
        storePath: String,
        command: (tool: String, arguments: [String]),
        basis: String,
        confidence: Confidence,
        explanation: String,
        excluded: inout [String]
    ) -> CleanupCandidate? {
        if environment.config.isExcluded(storePath) {
            excluded.append(storePath)
            return nil
        }
        let measurement = environment.measure(storePath)
        guard measurement.bytes > 0 else { return nil }

        return CleanupCandidate(
            id: id,
            title: title,
            source: source,
            action: .command(tool: command.tool, arguments: command.arguments),
            estimatedBytes: measurement.bytes,
            estimateBasis: basis + (measurement.isComplete ? "" : " (partial measurement)"),
            risk: .low,
            confidence: confidence,
            explanation: explanation,
            storePath: storePath
        )
    }

    // MARK: - Direct-delete candidates

    /// Well-known generated/cache paths Maclovin may remove itself
    /// (PRD "Allowed Cleanup Targets"). Estimates here are measured now and
    /// re-measured immediately before applying.
    func directDeleteCandidates(excluded: inout [String]) -> [CleanupCandidate] {
        let home = environment.home
        let targets: [(id: String, title: String, source: String, path: String, explanation: String)] = [
            (
                "xcode-derived-data",
                "Xcode DerivedData",
                "Xcode",
                home + "/Library/Developer/Xcode/DerivedData",
                "Build products and indexes; Xcode regenerates them on the next build."
            ),
            (
                "cargo-registry-cache",
                "Cargo registry download cache",
                "Cargo",
                home + "/.cargo/registry/cache",
                "Downloaded .crate archives; Cargo re-downloads on demand."
            ),
            (
                "user-logs",
                "User logs",
                "Logs",
                home + "/Library/Logs",
                "Generated application and diagnostic logs under ~/Library/Logs."
            )
        ]

        return targets.compactMap { target in
            if environment.config.isExcluded(target.path) {
                excluded.append(target.path)
                return nil
            }
            let measurement = environment.measure(target.path)
            guard measurement.bytes > 0 else { return nil }

            return CleanupCandidate(
                id: target.id,
                title: target.title,
                source: target.source,
                action: .deletePaths([target.path]),
                estimatedBytes: measurement.bytes,
                estimateBasis: "on-disk size measured by walking the target tree"
                    + (measurement.isComplete ? "" : " (partial measurement)"),
                risk: .low,
                confidence: .high,
                explanation: target.explanation
            )
        }
    }

    // MARK: - Audit-only findings

    /// Reported for context, never offered for cleanup
    /// (PRD "Audit-Only Targets").
    func auditOnlyFindings(excluded: inout [String]) -> [AuditOnlyFinding] {
        let home = environment.home
        let targets: [(title: String, path: String, note: String)] = [
            (
                "Docker data",
                home + "/Library/Containers/com.docker.docker",
                "Review in Docker Desktop or with `docker system df`; Maclovin never prunes Docker by default."
            ),
            ("nvm Node versions", home + "/.nvm/versions", "Installed runtimes; remove with `nvm uninstall`."),
            ("pyenv Python versions", home + "/.pyenv/versions", "Installed runtimes; remove with `pyenv uninstall`."),
            ("rbenv Ruby versions", home + "/.rbenv/versions", "Installed runtimes; remove with `rbenv uninstall`."),
            ("asdf installs", home + "/.asdf/installs", "Installed runtimes; remove with `asdf uninstall`."),
            ("SDKMAN installs", home + "/.sdkman/candidates", "Installed SDKs; remove with `sdk uninstall`."),
            ("rustup toolchains", home + "/.rustup/toolchains", "Installed toolchains; remove with `rustup toolchain uninstall`.")
        ]

        return targets
            .compactMap { target -> AuditOnlyFinding? in
                if environment.config.isExcluded(target.path) {
                    excluded.append(target.path)
                    return nil
                }
                let measurement = environment.measure(target.path)
                guard measurement.bytes > 0 else { return nil }
                return AuditOnlyFinding(
                    title: target.title,
                    path: target.path,
                    bytes: measurement.bytes,
                    note: target.note
                )
            }
            .sorted { $0.bytes > $1.bytes }
    }

    // MARK: - Brew dry-run parsing

    /// Parses `brew cleanup --dry-run` output: prefers the summary line
    /// "This operation would free approximately 131.7MB of disk space.",
    /// falling back to summing the per-item "(1.2MB)" suffixes. Item count is
    /// the number of "Would remove:" lines.
    public static func parseBrewDryRun(_ output: String) -> (bytes: UInt64, itemCount: Int) {
        var itemCount = 0
        var summedItemBytes: UInt64 = 0
        var approximateBytes: UInt64?

        for line in output.split(separator: "\n") {
            if line.contains("Would remove:") {
                itemCount += 1
                if let size = trailingParenthesizedSize(String(line)) {
                    summedItemBytes += size
                }
            } else if line.contains("would free approximately"),
                      let size = parseHumanSize(in: String(line)) {
                approximateBytes = size
            }
        }

        return (approximateBytes ?? summedItemBytes, itemCount)
    }

    /// Extracts the "(1.2MB)" suffix brew appends to each removal line.
    static func trailingParenthesizedSize(_ line: String) -> UInt64? {
        guard let open = line.lastIndex(of: "("), let close = line.lastIndex(of: ")"), open < close else {
            return nil
        }
        return parseHumanSize(in: String(line[line.index(after: open)..<close]))
    }

    /// Parses the first human-readable size ("131.7MB", "1.2GB", "804KB") in
    /// the text. Brew formats sizes with 1024-based units, matching ByteSize.
    public static func parseHumanSize(in text: String) -> UInt64? {
        let units: [(String, Double)] = [
            ("TB", 1024 * 1024 * 1024 * 1024),
            ("GB", 1024 * 1024 * 1024),
            ("MB", 1024 * 1024),
            ("KB", 1024),
            ("B", 1)
        ]

        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(TB|GB|MB|KB|B)"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let numberRange = Range(match.range(at: 1), in: text),
            let unitRange = Range(match.range(at: 2), in: text),
            let number = Double(text[numberRange])
        else {
            return nil
        }

        let unit = String(text[unitRange])
        guard let multiplier = units.first(where: { $0.0 == unit })?.1 else { return nil }
        return UInt64(number * multiplier)
    }
}
