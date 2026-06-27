import MaclovinCore
import Testing

@Test
func scansOnlyDotAppBundlesSortedBySize() {
    let dir = Fixture.tempDir()
    defer { Fixture.remove(dir) }

    for name in ["Big.app", "Small.app", "notes.txt"] {
        Fixture.makeDir(Fixture.join(dir, name))
    }

    let sizes: [String: UInt64] = ["Big.app": 900, "Small.app": 100]
    let result = AppScanner.scan(directoryPaths: [dir]) { path in
        let base = String(path.split(separator: "/").last ?? "")
        return SizeMeasurement(bytes: sizes[base] ?? 0, fileCount: 1, unreadableCount: 0)
    }

    #expect(result.entries.map(\.name) == ["Big", "Small"])
    #expect(result.entries.allSatisfy { $0.confidence == .high })
    #expect(result.totalBytes == 1000)
    #expect(result.skippedDirectories.isEmpty)
}

@Test
func reportsMissingDirectoriesAsSkipped() {
    let parent = Fixture.tempDir()
    defer { Fixture.remove(parent) }
    let missing = Fixture.join(parent, "does-not-exist")

    let result = AppScanner.scan(directoryPaths: [missing]) { _ in
        SizeMeasurement(bytes: 0, fileCount: 0, unreadableCount: 0)
    }

    #expect(result.entries.isEmpty)
    #expect(result.skippedDirectories == [missing])
}
