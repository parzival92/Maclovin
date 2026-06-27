import ArgumentParser
import MaclovinCore

struct AppsUninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Dry-run or apply an app uninstall after explicit review."
    )

    @Argument(help: "The app name to inspect.")
    var appName: String

    @Flag(exclusivity: .exclusive, help: "Choose dry-run review or apply mode.")
    var mode: ExecutionMode = .dryRun

    func run() throws {
        if mode == .apply {
            throw ValidationError("App uninstall apply is not implemented in this scaffold. No files were changed.")
        }

        print(
            ReportPrinter.render(
                title: "App Uninstall Dry Run",
                sections: [
                    ReportSection(
                        title: "Target",
                        rows: [
                            ReportRow("App", appName),
                            ReportRow("Mode", mode.label),
                            ReportRow("Writes", "none")
                        ]
                    ),
                    ReportSection(
                        title: "Planned Safety Gates",
                        rows: [
                            ReportRow("Bundle", "move .app to Trash"),
                            ReportRow("Related data", "separate cleanup review"),
                            ReportRow("Confirmation", "exact typed confirmation before apply")
                        ]
                    )
                ]
            )
        )
    }
}
