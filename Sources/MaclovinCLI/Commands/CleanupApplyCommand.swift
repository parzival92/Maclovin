import ArgumentParser

struct CleanupApplyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Apply selected cleanup candidates after explicit confirmation."
    )

    func run() throws {
        throw ValidationError("Cleanup apply is not implemented in this scaffold. No files were changed.")
    }
}
