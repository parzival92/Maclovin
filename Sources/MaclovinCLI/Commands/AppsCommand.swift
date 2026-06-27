import ArgumentParser

struct AppsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apps",
        abstract: "Audit application-related storage and uninstall apps with review gates.",
        subcommands: [
            AppsAuditCommand.self,
            AppsUninstallCommand.self
        ]
    )
}
