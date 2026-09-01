import Foundation

/// How a cleanup candidate's space is reclaimed.
///
/// The mode decides *how the estimate is produced* and *how bytes actually
/// freed are measured*, so the two are always reconciled on the same basis
/// (see issue #5). Maclovin's trust premise depends on this being explicit:
/// every candidate states where its estimate came from and how the freed
/// figure was obtained.
public enum CleanupMode: String, CaseIterable, Sendable {
    /// Reclaimed by delegating to an official tool command — for example
    /// `brew cleanup`, `npm cache clean`, `pip cache purge`, or
    /// `pnpm store prune`. Maclovin does not choose which bytes are removed;
    /// the tool does.
    case officialCommand
    /// Reclaimed by Maclovin directly removing a well-known generated/cache
    /// path — for example Xcode DerivedData or a generated log folder.
    case directDelete

    public var label: String {
        switch self {
        case .officialCommand:
            "Official command"
        case .directDelete:
            "Direct delete"
        }
    }

    /// How the pre-apply *estimate* is produced for this mode.
    public var estimateMethod: String {
        switch self {
        case .officialCommand:
            "Parsed from the tool's own dry-run output (for example `brew cleanup --dry-run`); Maclovin does not pre-measure paths it will not remove itself."
        case .directDelete:
            "On-disk size measured by walking the target tree with DirectorySizer immediately before applying, so the estimate reflects current contents."
        }
    }

    /// How *bytes actually freed* are measured for this mode.
    public var measurementMethod: String {
        switch self {
        case .officialCommand:
            "Before/after on-disk delta of the tool's managed store (for example the Homebrew cache), because the tool decides what it removes."
        case .directDelete:
            "Per-candidate: the target tree is re-measured after removal and freed = measured-before minus measured-after."
        }
    }
}

/// A single cleanup candidate's pre-apply estimate.
public struct CleanupEstimate: Equatable, Sendable {
    public let candidateID: String
    public let title: String
    public let mode: CleanupMode
    /// Bytes Maclovin expects to reclaim, produced per ``CleanupMode/estimateMethod``.
    public let estimatedBytes: UInt64

    public init(candidateID: String, title: String, mode: CleanupMode, estimatedBytes: UInt64) {
        self.candidateID = candidateID
        self.title = title
        self.mode = mode
        self.estimatedBytes = estimatedBytes
    }

    public var estimatedSize: ByteSize { ByteSize(estimatedBytes) }
}

/// The outcome of attempting one candidate during `cleanup apply`.
public enum CleanupStatus: String, Sendable {
    /// The candidate was applied; ``CleanupOutcome/freedBytes`` was measured.
    case succeeded
    /// The candidate was attempted but the command or deletion failed.
    case failed
    /// The candidate was never attempted (for example the batch stopped early
    /// after an earlier failure).
    case skipped
}

/// The measured result of attempting one candidate.
public struct CleanupOutcome: Equatable, Sendable {
    public let candidateID: String
    public let status: CleanupStatus
    /// Bytes actually freed, measured per ``CleanupMode/measurementMethod``.
    /// Always zero for ``CleanupStatus/failed`` and ``CleanupStatus/skipped``.
    public let freedBytes: UInt64
    /// Optional human-readable note: a failure reason, or why only part of the
    /// estimate was freed.
    public let note: String?

    public init(candidateID: String, status: CleanupStatus, freedBytes: UInt64 = 0, note: String? = nil) {
        self.candidateID = candidateID
        // Failed and skipped candidates freed nothing, by definition.
        self.status = status
        self.freedBytes = status == .succeeded ? freedBytes : 0
        self.note = note
    }

    public var freedSize: ByteSize { ByteSize(freedBytes) }
}

/// One candidate's estimate paired with what was actually freed.
public struct CandidateReconciliation: Equatable, Sendable {
    public let estimate: CleanupEstimate
    public let outcome: CleanupOutcome

    public init(estimate: CleanupEstimate, outcome: CleanupOutcome) {
        self.estimate = estimate
        self.outcome = outcome
    }

    public var candidateID: String { estimate.candidateID }
    public var title: String { estimate.title }
    public var mode: CleanupMode { estimate.mode }
    public var status: CleanupStatus { outcome.status }
    public var estimatedBytes: UInt64 { estimate.estimatedBytes }
    public var freedBytes: UInt64 { outcome.freedBytes }

    /// Freed minus estimated, signed: negative means Maclovin freed less than it
    /// estimated, positive means it freed more.
    public var varianceBytes: Int64 {
        Int64(bitPattern: freedBytes) - Int64(bitPattern: estimatedBytes)
    }

    /// freed / estimated as a fraction (1.0 == exactly on estimate). `nil` when
    /// nothing was estimated, since accuracy is undefined against a zero baseline.
    public var accuracy: Double? {
        guard estimatedBytes > 0 else { return nil }
        return Double(freedBytes) / Double(estimatedBytes)
    }

    /// A single line summarizing the reconciliation, for `cleanup apply` output
    /// and history entries — for example `est 1.2 GB -> freed 1.1 GB (succeeded, -100 MB)`.
    /// The verdict on its own, without the figures: what happened, and how
    /// close the estimate was.
    public var statusDetail: String {
        var detail = status.rawValue
        if status == .succeeded {
            detail += ", \(Self.formatVariance(varianceBytes))"
        }
        return detail
    }

    public var summaryLine: String {
        let estimated = estimate.estimatedSize.formatted
        let freed = outcome.freedSize.formatted
        var detail = status.rawValue
        if status == .succeeded {
            detail += ", \(Self.formatVariance(varianceBytes))"
        }
        return "est \(estimated) -> freed \(freed) (\(detail))"
    }

    static func formatVariance(_ variance: Int64) -> String {
        if variance == 0 { return "on estimate" }
        let sign = variance < 0 ? "-" : "+"
        let magnitude = UInt64(variance.magnitude)
        return "\(sign)\(ByteSize(magnitude).formatted)"
    }
}

/// The full estimate-vs-actual reconciliation for a `cleanup apply` batch.
///
/// Built by zipping each candidate's estimate with its measured outcome. The
/// report tolerates partial failure: candidates that succeeded before a failure
/// still count toward ``totalFreedBytes``, and the ones that never ran are
/// surfaced as ``CleanupStatus/skipped`` rather than silently dropped.
public struct CleanupReconciliationReport: Equatable, Sendable {
    public let candidates: [CandidateReconciliation]

    public init(candidates: [CandidateReconciliation]) {
        self.candidates = candidates
    }

    /// Pairs estimates with outcomes by `candidateID`. Estimates with no matching
    /// outcome are reported as ``CleanupStatus/skipped``; the original estimate
    /// order is preserved so the user sees candidates in the order they reviewed.
    public static func reconcile(
        estimates: [CleanupEstimate],
        outcomes: [CleanupOutcome]
    ) -> CleanupReconciliationReport {
        let outcomesByID = Dictionary(outcomes.map { ($0.candidateID, $0) }, uniquingKeysWith: { _, last in last })
        let candidates = estimates.map { estimate -> CandidateReconciliation in
            let outcome = outcomesByID[estimate.candidateID]
                ?? CleanupOutcome(candidateID: estimate.candidateID, status: .skipped)
            return CandidateReconciliation(estimate: estimate, outcome: outcome)
        }
        return CleanupReconciliationReport(candidates: candidates)
    }

    public var totalEstimatedBytes: UInt64 {
        candidates.reduce(0) { $0 + $1.estimatedBytes }
    }

    /// Bytes freed so far across succeeded candidates. Meaningful even when the
    /// batch stopped early, so the user always learns how much was actually
    /// reclaimed before a failure.
    public var totalFreedBytes: UInt64 {
        candidates.reduce(0) { $0 + $1.freedBytes }
    }

    public var totalEstimatedSize: ByteSize { ByteSize(totalEstimatedBytes) }
    public var totalFreedSize: ByteSize { ByteSize(totalFreedBytes) }

    public func candidates(with status: CleanupStatus) -> [CandidateReconciliation] {
        candidates.filter { $0.status == status }
    }

    public var succeeded: [CandidateReconciliation] { candidates(with: .succeeded) }
    public var failed: [CandidateReconciliation] { candidates(with: .failed) }
    public var skipped: [CandidateReconciliation] { candidates(with: .skipped) }

    /// True when every candidate succeeded — no failures and nothing skipped.
    public var isComplete: Bool {
        candidates.allSatisfy { $0.status == .succeeded }
    }

    /// True when at least one candidate succeeded and at least one did not, i.e.
    /// the batch only partially completed.
    public var isPartial: Bool {
        !candidates.isEmpty && !isComplete && !succeeded.isEmpty
    }

    /// Renders the reconciliation as report sections shared by `cleanup apply`
    /// output and `history show`: one row per candidate plus a totals summary.
    public func reportSections() -> [ReportSection] {
        // Estimate and freed figures are padded to a common width so the two
        // columns can be compared down the list, not just within a row.
        let estimateWidth = candidates.map { $0.estimate.estimatedSize.formatted.count }.max() ?? 0
        let freedWidth = candidates.map { $0.outcome.freedSize.formatted.count }.max() ?? 0
        let candidateRows = candidates.map { candidate in
            ReportRow(
                candidate.title,
                "est \(TerminalStyle.padLeading(candidate.estimate.estimatedSize.formatted, to: estimateWidth))"
                    + "  ->  freed \(TerminalStyle.padLeading(candidate.outcome.freedSize.formatted, to: freedWidth))",
                note: candidate.statusDetail
            )
        }

        var summaryRows = [
            ReportRow("Estimated total", totalEstimatedSize.formatted),
            ReportRow("Freed total", totalFreedSize.formatted)
        ]
        if !failed.isEmpty {
            summaryRows.append(ReportRow("Failed", "\(failed.count)"))
        }
        if !skipped.isEmpty {
            summaryRows.append(ReportRow("Skipped", "\(skipped.count)"))
        }
        let state = isComplete ? "complete" : (isPartial ? "partial" : "no candidates freed")
        summaryRows.append(ReportRow("Result", state))

        return [
            ReportSection(title: "Per-Candidate Estimate vs Actual", rows: candidateRows),
            ReportSection(title: "Totals", rows: summaryRows)
        ]
    }
}
