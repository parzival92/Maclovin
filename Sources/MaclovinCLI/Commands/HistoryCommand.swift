import ArgumentParser
import MaclovinCore

struct HistoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Show local scan and cleanup history summaries."
    )

    func run() throws {
        print(
            ReportPrinter.render(
                title: "Maclovin History",
                sections: [
                    ReportSection(
                        title: "Status",
                        rows: [
                            ReportRow("Implementation", "scaffold"),
                            ReportRow("History directory", MaclovinPaths.historyDirectory.path),
                            ReportRow("Stored data", "summaries and action logs only")
                        ]
                    )
                ],
                footer: [
                    "No history is written by this scaffold."
                ]
            )
        )
    }
}
