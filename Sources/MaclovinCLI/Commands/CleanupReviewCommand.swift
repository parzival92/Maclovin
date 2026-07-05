import ArgumentParser
import Foundation
import MaclovinCore

struct CleanupReviewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review",
        abstract: "Pick cleanup candidates interactively, then apply after confirmation."
    )

    func run() throws {
        let config = ConfigFile.load()
        let scan = CleanupScanner(environment: .live(config: config)).scan()

        guard !scan.candidates.isEmpty else {
            print(
                ReportPrinter.render(
                    title: "Cleanup Review",
                    sections: [
                        ReportSection(
                            title: "Status",
                            rows: [ReportRow("Candidates", "none found"), ReportRow("Writes", "none")]
                        )
                    ],
                    footer: ["Nothing within the cleanup boundary right now. See what was checked: maclovin cleanup scan"]
                )
            )
            return
        }

        let groups = CleanupReview.groups(for: scan.candidates)
        printPicker(groups, total: scan.totalEstimatedSize)

        print("")
        print("Select candidates to clean (numbers, ranges like 2-4, or 'all'; Enter cancels): ", terminator: "")
        fflush(stdout)

        let itemsByNumber = Dictionary(
            uniqueKeysWithValues: groups.flatMap(\.items).map { ($0.number, $0.candidate) }
        )

        switch CleanupReview.parseSelection(readLine(), count: itemsByNumber.count) {
        case .cancelled:
            print("Cancelled. No changes were made.")
        case .invalid(let reason):
            throw ValidationError(reason + ". No changes were made.")
        case .selected(let numbers):
            let candidates = numbers.compactMap { itemsByNumber[$0] }
            print("")
            try CleanupApplyFlow.confirmAndExecute(candidates, config: config)
        }
    }

    private func printPicker(_ groups: [CleanupReview.Group], total: ByteSize) {
        let sections = groups.map { group in
            ReportSection(
                title: "\(group.source) — up to \(group.totalEstimatedSize.formatted)",
                rows: group.items.flatMap { item in
                    [
                        CleanupApplyFlow.batchRow(item.candidate).numbered(item.number),
                        ReportRow("      why", item.candidate.explanation)
                    ]
                }
            )
        }

        print(
            ReportPrinter.render(
                title: "Cleanup Review",
                sections: sections,
                footer: ["Total: up to \(total.formatted) across \(groups.reduce(0) { $0 + $1.items.count }) candidates. Nothing has been changed yet."]
            )
        )
    }
}

private extension ReportRow {
    func numbered(_ number: Int) -> ReportRow {
        ReportRow("[\(number)] \(label)", value)
    }
}
