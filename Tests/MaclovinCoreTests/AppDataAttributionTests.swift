import MaclovinCore
import Testing

private let sampleIndex = [
    InstalledApp(name: "Docker", path: "/Applications/Docker.app", bundleID: "com.docker.docker"),
    InstalledApp(name: "Cursor", path: "/Applications/Cursor.app", bundleID: "com.todesktop.230313mzl4w4u92")
]

@Test
func attributesByExactBundleID() {
    let dir = Fixture.tempDir()
    defer { Fixture.remove(dir) }
    Fixture.makeDir(Fixture.join(dir, "com.docker.docker"))

    let result = AppDataAttributor.attribute(directory: dir, source: .container, index: sampleIndex) { _ in
        SizeMeasurement(bytes: 24_000, fileCount: 1, unreadableCount: 0)
    }

    #expect(result.count == 1)
    #expect(result[0].appName == "Docker")
    #expect(result[0].confidence == .high)
}

@Test
func attributesTeamPrefixedGroupContainerAsHigh() {
    let dir = Fixture.tempDir()
    defer { Fixture.remove(dir) }
    Fixture.makeDir(Fixture.join(dir, "group.com.docker.docker"))

    let result = AppDataAttributor.attribute(directory: dir, source: .groupContainer, index: sampleIndex) { _ in
        SizeMeasurement(bytes: 1_000, fileCount: 1, unreadableCount: 0)
    }

    #expect(result[0].appName == "Docker")
    #expect(result[0].confidence == .high)
}

@Test
func attributesByDisplayNameAsMedium() {
    let dir = Fixture.tempDir()
    defer { Fixture.remove(dir) }
    Fixture.makeDir(Fixture.join(dir, "Cursor"))

    let result = AppDataAttributor.attribute(directory: dir, source: .applicationSupport, index: sampleIndex) { _ in
        SizeMeasurement(bytes: 500, fileCount: 1, unreadableCount: 0)
    }

    #expect(result[0].appName == "Cursor")
    #expect(result[0].confidence == .medium)
}

@Test
func attributesSameVendorPrefixAsLow() {
    let dir = Fixture.tempDir()
    defer { Fixture.remove(dir) }
    Fixture.makeDir(Fixture.join(dir, "com.docker.sandboxes"))

    let result = AppDataAttributor.attribute(directory: dir, source: .applicationSupport, index: sampleIndex) { _ in
        SizeMeasurement(bytes: 17_000, fileCount: 1, unreadableCount: 0)
    }

    #expect(result[0].appName == "Docker")
    #expect(result[0].confidence == .low)
}

@Test
func doesNotAttributeBroadApplePrefix() {
    let index = [InstalledApp(name: "iMovie", path: "/Applications/iMovie.app", bundleID: "com.apple.iMovieApp")]
    let dir = Fixture.tempDir()
    defer { Fixture.remove(dir) }
    Fixture.makeDir(Fixture.join(dir, "com.apple.Safari"))

    let result = AppDataAttributor.attribute(directory: dir, source: .caches, index: index) { _ in
        SizeMeasurement(bytes: 5_000, fileCount: 1, unreadableCount: 0)
    }

    #expect(result[0].appName == nil)
}

@Test
func leavesUnknownFolderUnattributed() {
    let dir = Fixture.tempDir()
    defer { Fixture.remove(dir) }
    Fixture.makeDir(Fixture.join(dir, "com.ghost.uninstalled"))

    let result = AppDataAttributor.attribute(directory: dir, source: .caches, index: sampleIndex) { _ in
        SizeMeasurement(bytes: 9_000, fileCount: 1, unreadableCount: 0)
    }

    #expect(result[0].appName == nil)
    #expect(result[0].isAttributed == false)
}

@Test
func auditorFoldsDataIntoFootprintAndUnattributedBucket() {
    let appsDir = Fixture.tempDir()
    let dataDir = Fixture.tempDir()
    defer { Fixture.remove(appsDir); Fixture.remove(dataDir) }

    // One real bundle whose Info.plist carries a bundle id.
    let bundle = Fixture.join(appsDir, "Docker.app")
    Fixture.makeDir(Fixture.join(bundle, "Contents"))
    Fixture.writePlist(Fixture.join(bundle, "Contents/Info.plist"), bundleID: "com.docker.docker")

    Fixture.makeDir(Fixture.join(dataDir, "com.docker.docker"))   // attributable
    Fixture.makeDir(Fixture.join(dataDir, "com.ghost.gone"))      // unattributed

    let sizes: [String: UInt64] = [
        "Docker.app": 1_000,
        "com.docker.docker": 24_000,
        "com.ghost.gone": 9_000
    ]
    let report = AppsAuditor.audit(
        appDirectories: [Fixture.url(appsDir)],
        dataDirectories: [(dataDir, .container)]
    ) { path in
        let base = String(path.split(separator: "/").last ?? "")
        return SizeMeasurement(bytes: sizes[base] ?? 0, fileCount: 1, unreadableCount: 0)
    }

    #expect(report.footprints.count == 1)
    #expect(report.footprints[0].name == "Docker")
    #expect(report.footprints[0].totalBytes == 25_000)
    #expect(report.unattributedBytes == 9_000)
}
