import ArgumentParser

struct BrewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "brew",
        abstract: "Audit Homebrew storage and package health.",
        subcommands: [
            BrewAuditCommand.self,
            BrewUninstallCommand.self
        ]
    )
}
