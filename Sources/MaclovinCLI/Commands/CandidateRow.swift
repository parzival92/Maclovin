import MaclovinCore

/// Renders cleanup candidates identically wherever they appear — `cleanup
/// scan`, the `cleanup review` picker, and the batch shown before an apply —
/// so a candidate looks the same at every step of the same decision.
enum CandidateRow {
    /// How much prose to print under a candidate.
    enum Rationale {
        /// Command and ID only.
        case action
        /// Adds what the candidate is and why it is safe to remove.
        case why
        /// Adds how the estimate was measured.
        case full
    }

    static func rows(
        _ entries: [(number: Int?, candidate: CleanupCandidate)],
        rationale: Rationale
    ) -> [ReportRow] {
        let sizeWidth = entries.map { $0.candidate.estimatedSize.formatted.count }.max() ?? 0
        return entries.map { row($0.candidate, number: $0.number, sizeWidth: sizeWidth, rationale: rationale) }
    }

    static func row(
        _ candidate: CleanupCandidate,
        number: Int? = nil,
        sizeWidth: Int = 0,
        rationale: Rationale
    ) -> ReportRow {
        let label = number.map { "[\($0)] \(candidate.title)" } ?? candidate.title
        let verdict = "[\(candidate.risk.label) risk, \(candidate.confidence.label.lowercased()) confidence]"
        let value = "est \(TerminalStyle.padLeading(candidate.estimatedSize.formatted, to: sizeWidth))"
            + "  \(styled(verdict, candidate.risk))"

        // The ID leads: it is the token the user types into `cleanup apply`.
        var notes = ["id: \(candidate.id)  ·  \(action(candidate))"]
        switch rationale {
        case .action:
            break
        case .why:
            notes.append(candidate.explanation)
        case .full:
            notes.append("\(candidate.explanation) Estimate: \(candidate.estimateBasis).")
        }
        return ReportRow(label, value, note: notes.joined(separator: "\n"))
    }

    /// Risk is the one thing colour is spent on here: it is what decides
    /// whether a candidate deserves a second look before it runs.
    private static func styled(_ text: String, _ risk: Risk) -> String {
        switch risk {
        case .low: TerminalStyle.green(text)
        case .medium: TerminalStyle.yellow(text)
        case .high: TerminalStyle.red(text)
        }
    }

    private static func action(_ candidate: CleanupCandidate) -> String {
        candidate.mode == .officialCommand
            ? "runs `\(candidate.action.displayed)`"
            : "deletes \(candidate.action.displayed)"
    }
}
