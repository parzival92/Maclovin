import MaclovinCore
import Testing

private func candidate(id: String, source: String, bytes: UInt64) -> CleanupCandidate {
    CleanupCandidate(
        id: id,
        title: id,
        source: source,
        action: .deletePaths(["/tmp/\(id)"]),
        estimatedBytes: bytes,
        estimateBasis: "test",
        risk: .low,
        confidence: .high,
        explanation: "test"
    )
}

@Test func groupsOrderBySourceTotalWithSequentialNumbering() {
    let groups = CleanupReview.groups(for: [
        candidate(id: "small-a", source: "A", bytes: 100),
        candidate(id: "big-b", source: "B", bytes: 5000),
        candidate(id: "big-a", source: "A", bytes: 200),
        candidate(id: "small-b", source: "B", bytes: 300)
    ])

    #expect(groups.map(\.source) == ["B", "A"], "groups sort by total estimate, largest first")
    #expect(groups[0].items.map(\.candidate.id) == ["big-b", "small-b"], "items sort largest first within a group")
    #expect(groups.flatMap(\.items).map(\.number) == [1, 2, 3, 4], "numbering runs sequentially across groups")
    #expect(groups[0].totalEstimatedBytes == 5300)
}

@Test func groupsWithEqualTotalsOrderBySourceName() {
    let groups = CleanupReview.groups(for: [
        candidate(id: "z", source: "Zeta", bytes: 100),
        candidate(id: "a", source: "Alpha", bytes: 100)
    ])
    #expect(groups.map(\.source) == ["Alpha", "Zeta"])
}

@Test func selectionParsesNumbersRangesAndAll() {
    #expect(CleanupReview.parseSelection("3", count: 5) == .selected([3]))
    #expect(CleanupReview.parseSelection("1,3", count: 5) == .selected([1, 3]))
    #expect(CleanupReview.parseSelection("2-4", count: 5) == .selected([2, 3, 4]))
    #expect(CleanupReview.parseSelection("1 3, 2-3", count: 5) == .selected([1, 2, 3]))
    #expect(CleanupReview.parseSelection("all", count: 3) == .selected([1, 2, 3]))
    #expect(CleanupReview.parseSelection("ALL", count: 2) == .selected([1, 2]))
    #expect(CleanupReview.parseSelection("1,1,1", count: 2) == .selected([1]))
}

@Test func emptySelectionCancels() {
    #expect(CleanupReview.parseSelection(nil, count: 3) == .cancelled)
    #expect(CleanupReview.parseSelection("", count: 3) == .cancelled)
    #expect(CleanupReview.parseSelection("   \n", count: 3) == .cancelled)
}

@Test func selectionRejectsOutOfRangeAndGarbage() {
    guard case .invalid = CleanupReview.parseSelection("0", count: 3) else {
        Issue.record("0 should be out of range")
        return
    }
    guard case .invalid = CleanupReview.parseSelection("4", count: 3) else {
        Issue.record("4 should be out of range for count 3")
        return
    }
    guard case .invalid = CleanupReview.parseSelection("2-9", count: 3) else {
        Issue.record("range beyond count should be invalid")
        return
    }
    guard case .invalid = CleanupReview.parseSelection("3-1", count: 3) else {
        Issue.record("reversed range should be invalid")
        return
    }
    guard case .invalid = CleanupReview.parseSelection("banana", count: 3) else {
        Issue.record("non-numeric input should be invalid")
        return
    }
}
