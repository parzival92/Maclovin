import ArgumentParser
import MaclovinCore

struct CleanupApplyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Apply selected cleanup candidates after explicit confirmation."
    )

    @Argument(help: "Candidate IDs from 'maclovin cleanup scan' (for example npm-cache brew-cleanup).")
    var candidateIDs: [String]

    func validate() throws {
        guard !candidateIDs.isEmpty else {
            throw ValidationError("Name at least one candidate ID; list them with 'maclovin cleanup scan'.")
        }
    }

    func run() throws {
        let config = ConfigFile.load()
        // Re-scan so estimates reflect current contents, not a stale listing.
        let scan = CleanupScanner(environment: .live(config: config)).scan()
        let candidates = try resolve(candidateIDs, from: scan)

        try CleanupApplyFlow.confirmAndExecute(candidates, config: config)
    }

    /// Maps requested IDs to scanned candidates, preserving the user's order
    /// and dropping duplicates. Unknown IDs abort before anything is shown.
    private func resolve(_ ids: [String], from scan: CleanupScanResult) throws -> [CleanupCandidate] {
        let byID = Dictionary(scan.candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var selected: [CleanupCandidate] = []
        var unknown: [String] = []
        var seen: Set<String> = []
        for id in ids where seen.insert(id).inserted {
            if let candidate = byID[id] {
                selected.append(candidate)
            } else {
                unknown.append(id)
            }
        }

        guard unknown.isEmpty else {
            let available = scan.candidates.map(\.id).joined(separator: ", ")
            throw ValidationError(
                "No current candidate with ID \(unknown.joined(separator: ", ")). "
                    + (available.isEmpty
                        ? "The scan found no candidates right now."
                        : "Current candidates: \(available).")
            )
        }
        return selected
    }
}
