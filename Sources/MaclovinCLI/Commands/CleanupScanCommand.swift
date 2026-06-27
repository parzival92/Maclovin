import ArgumentParser
import MaclovinCore

struct CleanupScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Find cleanup candidates without changing files."
    )

    func run() throws {
        print(
            ReportPrinter.render(
                title: "Cleanup Scan",
                sections: [
                    ReportSection(
                        title: "Status",
                        rows: [
                            ReportRow("Implementation", "scaffold"),
                            ReportRow("Writes", "none"),
                            ReportRow("Candidate model", "\(Risk.low.label) risk / \(Confidence.high.label) confidence labels ready")
                        ]
                    ),
                    ReportSection(
                        title: "Planned Sources",
                        rows: [
                            ReportRow("Official tools", "Homebrew, npm, yarn, pnpm, pip, Cargo"),
                            ReportRow("Generated data", "Xcode DerivedData, unavailable simulators, logs, temp folders"),
                            ReportRow("Audit-only", "Docker, version managers, project dependencies")
                        ]
                    )
                ]
            )
        )
    }
}
