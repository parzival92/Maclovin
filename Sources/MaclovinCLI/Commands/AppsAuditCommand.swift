import ArgumentParser
import MaclovinCore

struct AppsAuditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Explain application bundles and related application data."
    )

    @Option(name: .long, help: "Number of largest bundles to list.")
    var top: Int = 15

    func run() throws {
        let result = AppScanner.scan()

        var sections: [ReportSection] = [
            ReportSection(
                title: "Summary",
                rows: [
                    ReportRow("App bundles", "\(result.entries.count)"),
                    ReportRow("Total bundle size", result.totalSize.formatted),
                    ReportRow("Scanned", result.scannedDirectories.isEmpty ? "none" : result.scannedDirectories.joined(separator: ", ")),
                    ReportRow("Writes", "none")
                ]
            )
        ]

        if result.entries.isEmpty {
            sections.append(
                ReportSection(
                    title: "Largest Bundles",
                    rows: [ReportRow("(none found)", "")]
                )
            )
        } else {
            let listed = result.entries.prefix(max(0, top))
            let rows = listed.map { entry in
                ReportRow(
                    entry.name,
                    "\(entry.size.formatted) [\(entry.confidence.label)]\(entry.isComplete ? "" : " (partial)")"
                )
            }
            sections.append(ReportSection(title: "Largest Bundles", rows: rows))
        }

        if !result.skippedDirectories.isEmpty {
            sections.append(
                ReportSection(
                    title: "Skipped",
                    rows: result.skippedDirectories.map { ReportRow($0, "absent or unreadable") }
                )
            )
        }

        let footer = [
            "Sizes are on-disk allocated bytes. Hardlinks counted once; symlinks not followed.",
            "Bundle sizes only; related app support/container and developer-tool data are not yet attributed.",
            "These numbers are Maclovin's own measurement and do not reproduce macOS Storage Settings."
        ]

        print(ReportPrinter.render(title: "Applications Audit", sections: sections, footer: footer))
    }
}
