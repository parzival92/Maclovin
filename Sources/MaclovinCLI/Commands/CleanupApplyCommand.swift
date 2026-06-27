import ArgumentParser
import MaclovinCore

struct CleanupApplyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Apply selected cleanup candidates after explicit confirmation."
    )

    func run() throws {
        // Execution is not wired up in this scaffold, so no files are changed.
        // What is defined here is the estimate-vs-actual reconciliation contract
        // (see issue #5) that apply and history both report against.
        print(
            ReportPrinter.render(
                title: "Cleanup Apply",
                sections: [
                    ReportSection(
                        title: "Status",
                        rows: [
                            ReportRow("Implementation", "scaffold"),
                            ReportRow("Writes", "none"),
                            ReportRow("Confirmation", "typed 'apply' batch gate required before execution")
                        ]
                    ),
                    ReportSection(
                        title: "Estimate / Measurement Contract",
                        rows: [
                            ReportRow(CleanupMode.officialCommand.label + " estimate", CleanupMode.officialCommand.estimateMethod),
                            ReportRow(CleanupMode.officialCommand.label + " freed", CleanupMode.officialCommand.measurementMethod),
                            ReportRow(CleanupMode.directDelete.label + " estimate", CleanupMode.directDelete.estimateMethod),
                            ReportRow(CleanupMode.directDelete.label + " freed", CleanupMode.directDelete.measurementMethod)
                        ]
                    )
                ],
                footer: [
                    "On apply, each candidate reports estimated vs actual bytes freed.",
                    "Partial failures stop the batch: succeeded candidates keep their freed bytes,",
                    "remaining candidates are recorded as skipped, and history stores the same reconciliation."
                ]
            )
        )
    }
}
