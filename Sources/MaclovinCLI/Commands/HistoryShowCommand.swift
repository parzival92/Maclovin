import ArgumentParser

struct HistoryShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show one history entry."
    )

    @Argument(help: "History entry id, or 'latest'.")
    var entryID: String

    func run() throws {
        throw ValidationError("History entry '\(entryID)' is not available in this scaffold.")
    }
}
