import Foundation
import MaclovinCore
import Testing

/// An executor over the real filesystem with commands stubbed: `commands`
/// maps a joined command line to an action run in its place.
private func executor(
    commands: [String: @Sendable () throws -> ShellResult] = [:]
) -> CleanupExecutor {
    CleanupExecutor(
        environment: CleanupExecutor.Environment(
            runCommand: { tool, arguments in
                let line = ([tool] + arguments).joined(separator: " ")
                guard let stub = commands[line] else {
                    throw Shell.ShellError.toolNotFound(tool)
                }
                return try stub()
            }
        )
    )
}

private func directDeleteCandidate(id: String = "fixture-cache", path: String, staleEstimate: UInt64 = 1) -> CleanupCandidate {
    CleanupCandidate(
        id: id,
        title: "Fixture cache",
        source: "Test",
        action: .deletePaths([path]),
        estimatedBytes: staleEstimate,
        estimateBasis: "test",
        risk: .low,
        confidence: .high,
        explanation: "test"
    )
}

private func commandCandidate(id: String = "fixture-tool", commandLine: [String], storePath: String?) -> CleanupCandidate {
    CleanupCandidate(
        id: id,
        title: "Fixture tool",
        source: "Test",
        action: .command(tool: commandLine[0], arguments: Array(commandLine.dropFirst())),
        estimatedBytes: 4096,
        estimateBasis: "test",
        risk: .low,
        confidence: .high,
        explanation: "test",
        storePath: storePath
    )
}

@Test func directDeleteRemovesContentsKeepsFolderAndMeasuresFreed() throws {
    let dir = Fixture.tempDir()
    defer { Fixture.remove(dir) }
    Fixture.makeDir(dir + "/sub")
    Fixture.write(dir + "/sub/blob", bytes: 8192)
    Fixture.write(dir + "/top", bytes: 4096)
    let before = DirectorySizer.measure(atPath: dir).bytes

    let result = executor().execute([directDeleteCandidate(path: dir, staleEstimate: 99)])

    let candidate = try #require(result.report.candidates.first)
    #expect(candidate.status == .succeeded)
    #expect(candidate.estimatedBytes == before, "estimate is re-measured at apply time, not the stale scan figure")
    #expect(candidate.freedBytes > 0)
    #expect(candidate.freedBytes == before - DirectorySizer.measure(atPath: dir).bytes)
    #expect(FileManager.default.fileExists(atPath: dir), "the well-known folder itself is kept")
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir).isEmpty)
    #expect(result.errors.isEmpty)
}

@Test func emptyDirectDeleteTargetSucceedsWithNothingToRemove() throws {
    let dir = Fixture.tempDir()
    defer { Fixture.remove(dir) }
    let missing = dir + "/never-created"

    let result = executor().execute([directDeleteCandidate(path: missing)])

    let candidate = try #require(result.report.candidates.first)
    #expect(candidate.status == .succeeded)
    #expect(candidate.freedBytes == 0)
    #expect(candidate.outcome.note?.contains("already empty") == true)
}

@Test func officialCommandMeasuresManagedStoreDelta() throws {
    let store = Fixture.tempDir()
    defer { Fixture.remove(store) }
    Fixture.write(store + "/keep", bytes: 4096)
    Fixture.write(store + "/stale", bytes: 8192)
    let before = DirectorySizer.measure(atPath: store).bytes

    let result = executor(commands: [
        "fake-tool clean": {
            Fixture.remove(store + "/stale")
            return ShellResult(exitCode: 0, stdout: "", stderr: "")
        }
    ]).execute([commandCandidate(commandLine: ["fake-tool", "clean"], storePath: store)])

    let candidate = try #require(result.report.candidates.first)
    #expect(candidate.status == .succeeded)
    #expect(candidate.freedBytes == before - DirectorySizer.measure(atPath: store).bytes)
    #expect(candidate.freedBytes > 0)
}

@Test func storeThatGrewDuringCleanReportsZeroFreedNotUnderflow() throws {
    let store = Fixture.tempDir()
    defer { Fixture.remove(store) }
    Fixture.write(store + "/existing", bytes: 4096)

    let result = executor(commands: [
        "fake-tool clean": {
            Fixture.write(store + "/downloaded-mid-clean", bytes: 16384)
            return ShellResult(exitCode: 0, stdout: "", stderr: "")
        }
    ]).execute([commandCandidate(commandLine: ["fake-tool", "clean"], storePath: store)])

    let candidate = try #require(result.report.candidates.first)
    #expect(candidate.status == .succeeded)
    #expect(candidate.freedBytes == 0)
}

@Test func commandSucceedingWithoutStorePathStatesUnmeasured() throws {
    let result = executor(commands: [
        "fake-tool clean": { ShellResult(exitCode: 0, stdout: "", stderr: "") }
    ]).execute([commandCandidate(commandLine: ["fake-tool", "clean"], storePath: nil)])

    let candidate = try #require(result.report.candidates.first)
    #expect(candidate.status == .succeeded)
    #expect(candidate.freedBytes == 0)
    #expect(candidate.outcome.note?.contains("not measured") == true)
}

@Test func failingCommandStopsBatchAndSkipsTheRest() throws {
    let untouched = Fixture.tempDir()
    defer { Fixture.remove(untouched) }
    Fixture.write(untouched + "/blob", bytes: 4096)

    let failing = commandCandidate(id: "first", commandLine: ["fake-tool", "clean"], storePath: nil)
    let never = directDeleteCandidate(id: "second", path: untouched)

    let result = executor(commands: [
        "fake-tool clean": { ShellResult(exitCode: 1, stdout: "", stderr: "Error: boom\nmore detail") }
    ]).execute([failing, never])

    #expect(result.report.candidates.map(\.status) == [.failed, .skipped])
    let first = try #require(result.report.candidates.first)
    #expect(first.outcome.note == "Error: boom")
    #expect(first.freedBytes == 0)
    #expect(result.errors == ["Fixture tool: Error: boom"])
    #expect(DirectorySizer.measure(atPath: untouched).bytes > 0, "skipped candidates are never executed")
    #expect(result.report.isPartial == false)
}

@Test func missingToolIsAFailureWithTheToolNamed() throws {
    let result = executor().execute([commandCandidate(commandLine: ["ghost-tool", "clean"], storePath: nil)])

    let candidate = try #require(result.report.candidates.first)
    #expect(candidate.status == .failed)
    #expect(candidate.outcome.note?.contains("ghost-tool") == true)
}

@Test func successBeforeFailureKeepsItsFreedBytes() throws {
    let cache = Fixture.tempDir()
    defer { Fixture.remove(cache) }
    Fixture.write(cache + "/blob", bytes: 8192)
    let before = DirectorySizer.measure(atPath: cache).bytes

    let result = executor(commands: [
        "fake-tool clean": { ShellResult(exitCode: 1, stdout: "", stderr: "broke") }
    ]).execute([
        directDeleteCandidate(id: "first", path: cache),
        commandCandidate(id: "second", commandLine: ["fake-tool", "clean"], storePath: nil)
    ])

    #expect(result.report.candidates.map(\.status) == [.succeeded, .failed])
    #expect(result.report.totalFreedBytes == before)
    #expect(result.report.isPartial)
}
