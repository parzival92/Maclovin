import ArgumentParser
import MaclovinCore

struct CleanupReviewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review",
        abstract: "Review cleanup candidates interactively before apply."
    )

    func run() throws {
        print(
            ReportPrinter.render(
                title: "Cleanup Review",
                sections: [
                    ReportSection(
                        title: "Status",
                        rows: [
                            ReportRow("Implementation", "scaffold"),
                            ReportRow("Writes", "none"),
                            ReportRow("Selection", "interactive picker planned")
                        ]
                    )
                ],
                footer: [
                    "Run maclovin cleanup scan once scanners are implemented."
                ]
            )
        )
    }
}
