import ArgumentParser

struct CleanupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cleanup",
        abstract: "Find, review, and apply cleanup candidates.",
        subcommands: [
            CleanupScanCommand.self,
            CleanupReviewCommand.self,
            CleanupApplyCommand.self
        ]
    )
}
