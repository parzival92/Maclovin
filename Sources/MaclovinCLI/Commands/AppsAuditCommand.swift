import ArgumentParser
import MaclovinCore

struct AppsAuditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Explain application bundles and related application data."
    )

    func run() throws {
        print(
            ReportPrinter.render(
                title: "Applications Audit",
                sections: [
                    ReportSection(
                        title: "Status",
                        rows: [
                            ReportRow("Implementation", "scaffold"),
                            ReportRow("Attribution", "confidence labels ready"),
                            ReportRow("Writes", "none")
                        ]
                    ),
                    ReportSection(
                        title: "Planned Sources",
                        rows: [
                            ReportRow("App bundles", "/Applications, ~/Applications"),
                            ReportRow("App data", "~/Library/Application Support, Containers, Group Containers"),
                            ReportRow("Developer tools", "Xcode, iOS Simulator, Docker, Homebrew casks")
                        ]
                    )
                ]
            )
        )
    }
}
