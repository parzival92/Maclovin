import ArgumentParser
import MaclovinCore

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check local tool availability and scan prerequisites."
    )

    func run() throws {
        print(
            ReportPrinter.render(
                title: "Maclovin Doctor",
                sections: [
                    ReportSection(
                        title: "Status",
                        rows: [
                            ReportRow("Implementation", "scaffold"),
                            ReportRow("Writes", "none"),
                            ReportRow("Missing tools", "will be warnings, not failures")
                        ]
                    ),
                    ReportSection(
                        title: "Planned Checks",
                        rows: [
                            ReportRow("System", "macOS version, architecture, disk space"),
                            ReportRow("Tools", "Homebrew, Xcode Command Line Tools, Docker"),
                            ReportRow("Access", "scan paths and Trash availability")
                        ]
                    )
                ]
            )
        )
    }
}
