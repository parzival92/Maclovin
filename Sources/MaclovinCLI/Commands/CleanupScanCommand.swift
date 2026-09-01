import ArgumentParser
import MaclovinCore

struct CleanupScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Find cleanup candidates without changing files."
    )

    func run() throws {
        let result = CleanupScanner(environment: .live()).scan()

        var sections: [ReportSection] = [
            ReportSection(
                title: "Summary",
                rows: [
                    ReportRow("Candidates", "\(result.candidates.count)"),
                    ReportRow("Estimated reclaimable", "up to \(result.totalEstimatedSize.formatted)"),
                    ReportRow("Audit-only findings", "\(result.auditOnly.count)"),
                    ReportRow("Writes", "none")
                ]
            )
        ]

        if !result.candidates.isEmpty {
            sections.append(
                ReportSection(
                    title: "Candidates (largest first)",
                    rows: CandidateRow.rows(result.candidates.map { (nil, $0) }, rationale: .full)
                )
            )
        }

        if !result.auditOnly.isEmpty {
            sections.append(
                ReportSection(
                    title: "Audit-Only (never offered for cleanup)",
                    rows: result.auditOnly.map { finding in
                        ReportRow(finding.title, finding.size.formatted, note: "\(finding.path)\n\(finding.note)")
                    }
                )
            )
        }

        if !result.excluded.isEmpty {
            sections.append(
                ReportSection(
                    title: "Excluded by config",
                    rows: result.excluded.map { ReportRow("skipped", $0) }
                )
            )
        }

        print(
            ReportPrinter.render(
                title: "Cleanup Scan",
                sections: sections,
                footer: [
                    "Nothing was changed. Select and apply candidates with: maclovin cleanup review",
                    "Estimates are on-disk allocated bytes; official commands decide what they actually remove, so some stores may free less than estimated."
                ]
            )
        )
    }
}
