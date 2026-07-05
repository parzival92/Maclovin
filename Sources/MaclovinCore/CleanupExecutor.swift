import Foundation

/// Executes a confirmed batch of cleanup candidates and measures what was
/// actually freed, per the estimate/measurement contract (issue #5):
///
/// - Official-command candidates run their tool; freed bytes are the
///   before/after on-disk delta of the tool's managed store.
/// - Direct-delete candidates are re-measured immediately before removal (that
///   fresh measurement replaces the scan-time estimate) and re-measured after,
///   so freed = before − after.
/// - A failure stops the batch: succeeded candidates keep their measured freed
///   bytes and the remaining candidates are recorded as skipped.
///
/// The executor assumes confirmation already happened; callers gate it behind
/// ``Confirmation`` and never invoke it otherwise.
public struct CleanupExecutor: Sendable {
    /// Everything the executor touches, injectable for tests.
    public struct Environment: Sendable {
        public var runCommand: @Sendable (_ tool: String, _ arguments: [String]) throws -> ShellResult
        public var measure: @Sendable (_ path: String) -> SizeMeasurement
        public var removeItem: @Sendable (_ path: String) throws -> Void
        /// Directory children, or nil when the path is not a listable directory.
        public var childrenOf: @Sendable (_ path: String) -> [String]?

        public init(
            runCommand: @escaping @Sendable (String, [String]) throws -> ShellResult,
            measure: @escaping @Sendable (String) -> SizeMeasurement = { DirectorySizer.measure(atPath: $0) },
            removeItem: @escaping @Sendable (String) throws -> Void = { try FileManager.default.removeItem(atPath: $0) },
            childrenOf: @escaping @Sendable (String) -> [String]? = { try? FileManager.default.contentsOfDirectory(atPath: $0) }
        ) {
            self.runCommand = runCommand
            self.measure = measure
            self.removeItem = removeItem
            self.childrenOf = childrenOf
        }

        public static func live() -> Environment {
            // Official cleanup commands can legitimately take minutes
            // (brew cleanup on a large cellar), hence the generous timeout.
            Environment(runCommand: { try Shell.run($0, $1, timeout: 600) })
        }
    }

    public struct BatchResult: Equatable, Sendable {
        public let report: CleanupReconciliationReport
        /// Failure reasons in batch order, phrased for the report's
        /// errors section and the history entry.
        public let errors: [String]
    }

    let environment: Environment

    public init(environment: Environment) {
        self.environment = environment
    }

    public func execute(_ candidates: [CleanupCandidate]) -> BatchResult {
        var estimates: [CleanupEstimate] = []
        var outcomes: [CleanupOutcome] = []
        var errors: [String] = []
        var batchStopped = false

        for candidate in candidates {
            if batchStopped {
                // Reconcile reports estimates without outcomes as skipped.
                estimates.append(candidate.estimate)
                continue
            }

            let attempted: (estimate: CleanupEstimate, outcome: CleanupOutcome)
            switch candidate.action {
            case .command(let tool, let arguments):
                attempted = runOfficialCommand(candidate, tool: tool, arguments: arguments)
            case .deletePaths(let paths):
                attempted = deleteDirectly(candidate, paths: paths)
            }

            estimates.append(attempted.estimate)
            outcomes.append(attempted.outcome)
            if attempted.outcome.status == .failed {
                errors.append("\(candidate.title): \(attempted.outcome.note ?? "failed")")
                batchStopped = true
            }
        }

        return BatchResult(
            report: .reconcile(estimates: estimates, outcomes: outcomes),
            errors: errors
        )
    }

    // MARK: - Official-command mode

    private func runOfficialCommand(
        _ candidate: CleanupCandidate,
        tool: String,
        arguments: [String]
    ) -> (estimate: CleanupEstimate, outcome: CleanupOutcome) {
        let estimate = candidate.estimate
        let storeBefore = candidate.storePath.map { environment.measure($0).bytes }

        let result: ShellResult
        do {
            result = try environment.runCommand(tool, arguments)
        } catch {
            return (estimate, CleanupOutcome(
                candidateID: candidate.id,
                status: .failed,
                note: "could not run \(tool): \(error)"
            ))
        }

        guard result.succeeded else {
            let reason = result.stderr
                .split(separator: "\n")
                .first
                .map(String.init) ?? "exit code \(result.exitCode)"
            return (estimate, CleanupOutcome(candidateID: candidate.id, status: .failed, note: reason))
        }

        guard let storePath = candidate.storePath, let before = storeBefore else {
            return (estimate, CleanupOutcome(
                candidateID: candidate.id,
                status: .succeeded,
                freedBytes: 0,
                note: "command succeeded; freed bytes not measured (no managed store path)"
            ))
        }

        let after = environment.measure(storePath).bytes
        // A store can grow mid-clean (concurrent downloads); report zero
        // rather than underflowing or inventing a negative figure.
        let freed = after < before ? before - after : 0
        return (estimate, CleanupOutcome(candidateID: candidate.id, status: .succeeded, freedBytes: freed))
    }

    // MARK: - Direct-delete mode

    private func deleteDirectly(
        _ candidate: CleanupCandidate,
        paths: [String]
    ) -> (estimate: CleanupEstimate, outcome: CleanupOutcome) {
        // The contract's fresh estimate: measured immediately before applying,
        // replacing the scan-time figure.
        let before = paths.reduce(UInt64(0)) { $0 + environment.measure($1).bytes }
        let estimate = CleanupEstimate(
            candidateID: candidate.id,
            title: candidate.title,
            mode: .directDelete,
            estimatedBytes: before
        )

        guard before > 0 else {
            return (estimate, CleanupOutcome(
                candidateID: candidate.id,
                status: .succeeded,
                freedBytes: 0,
                note: "nothing to remove; the target is already empty"
            ))
        }

        var failure: String?
        for path in paths {
            do {
                try deleteContents(of: path)
            } catch {
                failure = error.localizedDescription
                break
            }
        }

        let after = paths.reduce(UInt64(0)) { $0 + environment.measure($1).bytes }
        let freed = after < before ? before - after : 0

        if let failure {
            // CleanupOutcome records zero freed bytes for failures by
            // definition; state what was removed before the error instead.
            var note = failure
            if freed > 0 {
                note += "; \(ByteSize(freed).formatted) was removed before the error and is not counted"
            }
            return (estimate, CleanupOutcome(candidateID: candidate.id, status: .failed, note: note))
        }

        return (estimate, CleanupOutcome(candidateID: candidate.id, status: .succeeded, freedBytes: freed))
    }

    /// Removes a directory's contents but keeps the directory itself — apps
    /// expect well-known folders like ~/Library/Logs and DerivedData to exist.
    /// Plain files are removed directly.
    private func deleteContents(of path: String) throws {
        if let children = environment.childrenOf(path) {
            for child in children {
                try environment.removeItem(path + "/" + child)
            }
        } else {
            try environment.removeItem(path)
        }
    }
}
