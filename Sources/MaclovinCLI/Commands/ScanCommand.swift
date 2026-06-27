import ArgumentParser
import MaclovinCore

struct ScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Show a broad storage dashboard."
    )

    @Flag(name: .long, help: "Include slower user-library inspections when implemented.")
    var deep = false

    func run() throws {
        print(
            ReportPrinter.render(
                title: "Maclovin Scan",
                sections: [
                    ReportSection(
                        title: "Status",
                        rows: [
                            ReportRow("Mode", deep ? "deep" : "standard"),
                            ReportRow("Implementation", "scaffold"),
                            ReportRow("Writes", "none")
                        ]
                    ),
                    ReportSection(
                        title: "Next Commands",
                        rows: [
                            ReportRow("Applications", "maclovin apps audit"),
                            ReportRow("Homebrew", "maclovin brew audit"),
                            ReportRow("System checks", "maclovin doctor")
                        ]
                    )
                ],
                footer: [
                    "Storage scanners will be implemented in the next milestones."
                ]
            )
        )
    }
}
