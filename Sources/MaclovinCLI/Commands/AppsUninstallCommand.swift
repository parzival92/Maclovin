import ArgumentParser
import MaclovinCore

struct AppsUninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Dry-run or apply an app uninstall after explicit review."
    )

    @Argument(help: "The app to uninstall: display name, .app filename, or bundle identifier (case-insensitive).")
    var appName: String

    @Flag(exclusivity: .exclusive, help: "Choose dry-run review or apply mode.")
    var mode: ExecutionMode = .dryRun

    func run() throws {
        let app = try resolveTarget()

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
                            ReportRow("Query", appName),
                            ReportRow("Resolved app", app.name),
                            ReportRow("Bundle", app.path),
                            ReportRow("Bundle ID", app.bundleID ?? "unknown"),
                            ReportRow("Mode", mode.label),
                            ReportRow("Writes", "none")
                        ]
                    ),
                    ReportSection(
                        title: "Planned Safety Gates",
                        rows: [
                            ReportRow("Bundle", "move .app to Trash"),
                            ReportRow("Related data", "separate cleanup review"),
                            ReportRow("Confirmation", "type '\(app.name)' to confirm before apply")
                        ]
                    )
                ]
            )
        )
    }

    /// Resolves `appName` to a single installed bundle, surfacing not-found and
    /// ambiguous outcomes as validation errors before any further work.
    private func resolveTarget() throws -> InstalledApp {
        switch AppResolver.resolve(appName) {
        case .resolved(let app):
            return app
        case .notFound(let query):
            throw ValidationError(
                "No installed app matches '\(query)'. Try the display name, .app filename, or bundle identifier."
            )
        case .ambiguous(let query, let candidates):
            let list = candidates
                .map { "  - \($0.name)  (\($0.path))  [\($0.bundleID ?? "no bundle id")]" }
                .joined(separator: "\n")
            throw ValidationError(
                "'\(query)' is ambiguous; it matches \(Plural.count(candidates.count, "app")):\n\(list)\n"
                    + "Re-run with the bundle identifier to pick exactly one."
            )
        }
    }
}
