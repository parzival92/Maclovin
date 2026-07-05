import ArgumentParser
import Foundation
import MaclovinCore

/// The shared tail of `cleanup apply` and `cleanup review`: show the batch,
/// gate on typed confirmation, execute, report the reconciliation, and record
/// history.
enum CleanupApplyFlow {
    static func confirmAndExecute(_ candidates: [CleanupCandidate], config: ConfigFile) throws {
        printBatchSummary(candidates)

        let gate = config.gate(typedTarget: "apply")
        print("")
        print(Confirmation.promptLine(gate, action: "this cleanup batch"), terminator: "")
        fflush(stdout)
        guard Confirmation.evaluate(gate, input: readLine()) == .confirmed else {
            print("Aborted. No changes were made.")
            return
        }

        let result = CleanupExecutor(environment: .live()).execute(candidates)

        var sections = result.report.reportSections()
        if !result.errors.isEmpty {
            sections.append(
                ReportSection(title: "Errors", rows: result.errors.map { ReportRow("!", $0) })
            )
        }

        print("")
        print(
            ReportPrinter.render(
                title: "Cleanup Apply Result",
                sections: sections,
                footer: [recordHistory(result, config: config)]
            )
        )
        if !result.errors.isEmpty {
            throw ExitCode(1)
        }
    }

    static func batchRow(_ candidate: CleanupCandidate) -> ReportRow {
        ReportRow(
            candidate.title,
            "est \(candidate.estimatedSize.formatted)"
                + "  [\(candidate.risk.label) risk, \(candidate.confidence.label) confidence]"
                + (candidate.mode == .officialCommand
                    ? "  via `\(candidate.action.displayed)`"
                    : "  deletes \(candidate.action.displayed)")
        )
    }

    private static func printBatchSummary(_ candidates: [CleanupCandidate]) {
        let total = candidates.reduce(UInt64(0)) { $0 + $1.estimatedBytes }

        print(
            ReportPrinter.render(
                title: "Cleanup Apply",
                sections: [
                    ReportSection(
                        title: "Batch (\(candidates.count) candidates, up to \(ByteSize(total).formatted))",
                        rows: candidates.map(batchRow)
                    )
                ],
                footer: [
                    "Direct-delete estimates are re-measured immediately before removal.",
                    "Generated caches are permanently removed, not moved to Trash."
                ]
            )
        )
    }

    /// Writes the batch reconciliation to local history; history problems are
    /// warnings, never reasons to fail an action that already happened.
    private static func recordHistory(_ result: CleanupExecutor.BatchResult, config: ConfigFile) -> String {
        guard config.historyEnabled else {
            return "History is disabled in config; this batch was not recorded."
        }

        let report = result.report
        let entry = HistoryEntry(
            kind: .cleanupApply,
            summary: [
                "Freed \(report.totalFreedSize.formatted) of an estimated "
                    + "\(report.totalEstimatedSize.formatted) across \(report.candidates.count) candidates."
            ],
            candidates: report.candidates.map(HistoryEntry.CandidateRecord.init),
            errors: result.errors
        )

        do {
            let id = try HistoryStore.default.append(entry)
            return "Recorded in history: maclovin history show \(id)"
        } catch {
            return "Warning: the batch ran but history could not be written: \(error.localizedDescription)"
        }
    }
}
