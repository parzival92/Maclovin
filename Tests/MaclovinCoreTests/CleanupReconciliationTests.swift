import MaclovinCore
import Testing

private func estimate(
    _ id: String,
    mode: CleanupMode = .directDelete,
    bytes: UInt64
) -> CleanupEstimate {
    CleanupEstimate(candidateID: id, title: id, mode: mode, estimatedBytes: bytes)
}

@Test
func failedAndSkippedOutcomesFreeNothing() {
    let failed = CleanupOutcome(candidateID: "a", status: .failed, freedBytes: 999)
    let skipped = CleanupOutcome(candidateID: "b", status: .skipped, freedBytes: 999)
    #expect(failed.freedBytes == 0)
    #expect(skipped.freedBytes == 0)
}

@Test
func varianceIsSignedFreedMinusEstimated() {
    let under = CandidateReconciliation(
        estimate: estimate("a", bytes: 1000),
        outcome: CleanupOutcome(candidateID: "a", status: .succeeded, freedBytes: 600)
    )
    let over = CandidateReconciliation(
        estimate: estimate("b", bytes: 1000),
        outcome: CleanupOutcome(candidateID: "b", status: .succeeded, freedBytes: 1400)
    )
    #expect(under.varianceBytes == -400)
    #expect(over.varianceBytes == 400)
}

@Test
func accuracyIsNilWhenNothingWasEstimated() {
    let candidate = CandidateReconciliation(
        estimate: estimate("a", bytes: 0),
        outcome: CleanupOutcome(candidateID: "a", status: .succeeded, freedBytes: 100)
    )
    #expect(candidate.accuracy == nil)
}

@Test
func accuracyIsFreedOverEstimated() {
    let candidate = CandidateReconciliation(
        estimate: estimate("a", bytes: 1000),
        outcome: CleanupOutcome(candidateID: "a", status: .succeeded, freedBytes: 500)
    )
    #expect(candidate.accuracy == 0.5)
}

@Test
func reconcileMarksUnmatchedEstimatesAsSkipped() {
    let report = CleanupReconciliationReport.reconcile(
        estimates: [estimate("a", bytes: 100), estimate("b", bytes: 200)],
        outcomes: [CleanupOutcome(candidateID: "a", status: .succeeded, freedBytes: 90)]
    )
    #expect(report.candidates.count == 2)
    #expect(report.candidates[0].status == .succeeded)
    #expect(report.candidates[1].status == .skipped)
}

@Test
func reconcilePreservesEstimateOrder() {
    let report = CleanupReconciliationReport.reconcile(
        estimates: [estimate("first", bytes: 1), estimate("second", bytes: 2)],
        outcomes: [
            CleanupOutcome(candidateID: "second", status: .succeeded, freedBytes: 2),
            CleanupOutcome(candidateID: "first", status: .succeeded, freedBytes: 1)
        ]
    )
    #expect(report.candidates.map(\.candidateID) == ["first", "second"])
}

@Test
func totalsSumEstimatedAndFreedBytes() {
    let report = CleanupReconciliationReport.reconcile(
        estimates: [estimate("a", bytes: 1000), estimate("b", bytes: 2000), estimate("c", bytes: 500)],
        outcomes: [
            CleanupOutcome(candidateID: "a", status: .succeeded, freedBytes: 900),
            CleanupOutcome(candidateID: "b", status: .failed)
        ]
    )
    #expect(report.totalEstimatedBytes == 3500)
    // Only the succeeded candidate contributes freed bytes; failed and skipped free nothing.
    #expect(report.totalFreedBytes == 900)
}

@Test
func partialFailureIsSurfacedWithFreedBytesSoFar() {
    let report = CleanupReconciliationReport.reconcile(
        estimates: [estimate("a", bytes: 1000), estimate("b", bytes: 2000), estimate("c", bytes: 500)],
        outcomes: [
            CleanupOutcome(candidateID: "a", status: .succeeded, freedBytes: 1000),
            CleanupOutcome(candidateID: "b", status: .failed, note: "command exited non-zero")
        ]
    )
    #expect(report.isPartial)
    #expect(!report.isComplete)
    #expect(report.failed.map(\.candidateID) == ["b"])
    #expect(report.skipped.map(\.candidateID) == ["c"])
    #expect(report.totalFreedBytes == 1000)
}

@Test
func completeBatchHasNoFailuresOrSkips() {
    let report = CleanupReconciliationReport.reconcile(
        estimates: [estimate("a", bytes: 100), estimate("b", bytes: 200)],
        outcomes: [
            CleanupOutcome(candidateID: "a", status: .succeeded, freedBytes: 100),
            CleanupOutcome(candidateID: "b", status: .succeeded, freedBytes: 200)
        ]
    )
    #expect(report.isComplete)
    #expect(!report.isPartial)
}

@Test
func modesDescribeDistinctEstimateAndMeasurementMethods() {
    #expect(CleanupMode.officialCommand.estimateMethod != CleanupMode.directDelete.estimateMethod)
    #expect(CleanupMode.officialCommand.measurementMethod != CleanupMode.directDelete.measurementMethod)
}

@Test
func reportSectionsRenderPerCandidateAndTotals() {
    let report = CleanupReconciliationReport.reconcile(
        estimates: [estimate("DerivedData", bytes: 1000)],
        outcomes: [CleanupOutcome(candidateID: "DerivedData", status: .succeeded, freedBytes: 900)]
    )
    let sections = report.reportSections()
    #expect(sections.count == 2)
    #expect(sections[0].rows.count == 1)
    #expect(sections[0].rows[0].label == "DerivedData")
    #expect(sections[1].rows.contains { $0.label == "Result" && $0.value == "complete" })
}
