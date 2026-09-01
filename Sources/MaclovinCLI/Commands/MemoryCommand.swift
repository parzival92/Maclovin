import ArgumentParser

struct MemoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "memory",
        abstract: "Explain where physical memory went and what is reclaimable.",
        subcommands: [
            MemoryAuditCommand.self
        ]
    )
}
