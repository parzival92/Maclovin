import Foundation
import MaclovinCore
import Testing

private func temporaryStore() throws -> HistoryStore {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("maclovin-history-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return HistoryStore(directory: directory)
}

@Test
func appendAndListRoundTripsAnEntry() throws {
    let store = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: store.directory) }

    let entry = HistoryEntry(
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        kind: .cleanupApply,
        macOSVersion: "15.5.0",
        summary: ["Freed 1.2 GB of 1.3 GB estimated"],
        candidates: [],
        errors: ["one path skipped"]
    )
    let id = try store.append(entry)

    let listed = store.list()
    #expect(listed.count == 1)
    #expect(listed[0].id == id)
    #expect(listed[0].entry == entry)
    #expect(store.entry(id: id) == entry)
}

@Test
func listReturnsNewestFirstAndLatestPicksIt() throws {
    let store = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: store.directory) }

    let older = HistoryEntry(
        timestamp: Date(timeIntervalSince1970: 1_000),
        kind: .scan,
        macOSVersion: "15.0.0",
        summary: ["old scan"]
    )
    let newer = HistoryEntry(
        timestamp: Date(timeIntervalSince1970: 2_000),
        kind: .appUninstall,
        macOSVersion: "15.0.0",
        summary: ["Uninstalled Slack"]
    )
    try store.append(older)
    try store.append(newer)

    let listed = store.list()
    #expect(listed.map { $0.entry.kind } == [.appUninstall, .scan])
    #expect(store.latest()?.entry == newer)
}

@Test
func candidateRecordRoundTripsReconciliation() throws {
    let estimate = CleanupEstimate(
        candidateID: "xcode-derived-data",
        title: "Xcode DerivedData",
        mode: .directDelete,
        estimatedBytes: 1_000
    )
    let outcome = CleanupOutcome(
        candidateID: "xcode-derived-data",
        status: .succeeded,
        freedBytes: 900,
        note: "100 B recreated during removal"
    )
    let original = CandidateReconciliation(estimate: estimate, outcome: outcome)

    let record = HistoryEntry.CandidateRecord(original)
    #expect(record.reconciliation == original)

    let store = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let entry = HistoryEntry(kind: .cleanupApply, summary: ["cleanup"], candidates: [record])
    let id = try store.append(entry)
    #expect(store.entry(id: id)?.candidates.first?.reconciliation == original)
}

@Test
func unreadableFilesAreSkippedNotFatal() throws {
    let store = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: store.directory) }

    try Data("not json".utf8).write(to: store.directory.appendingPathComponent("garbage.json"))
    try store.append(HistoryEntry(kind: .scan, summary: ["ok"]))

    #expect(store.list().count == 1)
}
