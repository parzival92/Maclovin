import ArgumentParser

struct Maclovin: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "maclovin",
        abstract: "Understand and reduce disk usage on your Mac safely.",
        discussion: """
        Maclovin is local-first. Scaffolded commands are read-only unless a future apply or uninstall flow explicitly asks for confirmation.
        """,
        version: "0.1.0",
        subcommands: [
            ScanCommand.self,
            AppsCommand.self,
            BrewCommand.self,
            CleanupCommand.self,
            DoctorCommand.self,
            HistoryCommand.self
        ]
    )
}

Maclovin.main()
