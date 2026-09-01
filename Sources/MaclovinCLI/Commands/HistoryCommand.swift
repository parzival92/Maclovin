import ArgumentParser
import Foundation
import MaclovinCore

struct HistoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Show local scan and cleanup history summaries.",
        subcommands: [HistoryShowCommand.self]
    )

    @Option(name: .long, help: "Number of entries to list.")
    var limit: Int = 20

    func run() throws {
        let store = HistoryStore.default
        let entries = store.list().prefix(max(0, limit))

        guard !entries.isEmpty else {
            print(
                ReportPrinter.render(
                    title: "Maclovin History",
                    sections: [
                        ReportSection(
                            title: "Status",
                            rows: [
                                ReportRow("Entries", "none"),
                                ReportRow("History directory", store.directory.path)
                            ]
                        )
                    ],
                    footer: [
                        "History is written by scan, cleanup apply, and uninstall commands.",
                        "Disable with [history] enabled = false in ~/.config/maclovin/config.toml."
                    ]
                )
            )
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let rows = entries.map { id, entry in
            ReportRow(
                id,
                "\(entry.kind.label)  ·  \(formatter.string(from: entry.timestamp))",
                note: entry.headline
            )
        }

        print(
            ReportPrinter.render(
                title: "Maclovin History",
                sections: [ReportSection(title: "Recent Entries (newest first)", rows: rows)],
                footer: [
                    "Show full detail: maclovin history show latest  (or an entry ID from the list).",
                    "Stored locally in \(store.directory.path); summaries and action logs only."
                ]
            )
        )
    }
}

struct HistoryShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show one history entry in full, including per-candidate estimate vs actual."
    )

    @Argument(help: "'latest' or an entry ID from 'maclovin history'.")
    var entryID: String = "latest"

    func run() throws {
        let store = HistoryStore.default

        let found: (id: String, entry: HistoryEntry)?
        if entryID == "latest" {
            found = store.latest()
        } else if let entry = store.entry(id: entryID) {
            found = (entryID, entry)
        } else {
            found = nil
        }

        guard let (id, entry) = found else {
            throw ValidationError(
                entryID == "latest"
                    ? "No history entries exist yet. Run a scan or cleanup first."
                    : "No history entry with ID '\(entryID)'. List IDs with 'maclovin history'."
            )
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var sections: [ReportSection] = [
            ReportSection(
                title: "Entry",
                rows: [
                    ReportRow("ID", id),
                    ReportRow("Kind", entry.kind.label),
                    ReportRow("Timestamp", formatter.string(from: entry.timestamp)),
                    ReportRow("macOS", entry.macOSVersion)
                ]
            ),
            ReportSection(
                title: "Summary",
                rows: entry.summary.map { ReportRow($0, "") }
            )
        ]

        if !entry.candidates.isEmpty {
            let report = CleanupReconciliationReport(
                candidates: entry.candidates.map(\.reconciliation)
            )
            sections.append(contentsOf: report.reportSections())
        }

        if !entry.errors.isEmpty {
            sections.append(
                ReportSection(title: "Errors / Skipped", rows: entry.errors.map { ReportRow("! \($0)", "") })
            )
        }

        print(ReportPrinter.render(title: "History Entry", sections: sections))
    }
}
