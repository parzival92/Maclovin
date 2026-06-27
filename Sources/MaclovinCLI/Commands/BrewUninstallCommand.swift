import ArgumentParser
import MaclovinCore

struct BrewUninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Dry-run or apply a Homebrew uninstall after explicit review."
    )

    @Argument(help: "The formula or cask to inspect.")
    var packageName: String

    @Flag(exclusivity: .exclusive, help: "Choose dry-run review or apply mode.")
    var mode: ExecutionMode = .dryRun

    func run() throws {
        if mode == .apply {
            throw ValidationError("Homebrew uninstall apply is not implemented in this scaffold. No files were changed.")
        }

        print(
            ReportPrinter.render(
                title: "Homebrew Uninstall Dry Run",
                sections: [
                    ReportSection(
                        title: "Target",
                        rows: [
                            ReportRow("Package", packageName),
                            ReportRow("Mode", mode.label),
                            ReportRow("Writes", "none")
                        ]
                    ),
                    ReportSection(
                        title: "Planned Safety Gates",
                        rows: [
                            ReportRow("Impact", "dependents and cask/formula type"),
                            ReportRow("Execution", "delegate to brew uninstall"),
                            ReportRow("Confirmation", "exact typed confirmation before apply")
                        ]
                    )
                ]
            )
        )
    }
}
