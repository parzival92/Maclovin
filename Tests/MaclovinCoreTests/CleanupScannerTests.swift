import Foundation
import MaclovinCore
import Testing

/// Builds a scanner over a fixture home directory with no tools available
/// unless the test stubs them.
private func scanner(
    home: String,
    config: ConfigFile = .default,
    tools: [String: String] = [:]
) -> CleanupScanner {
    CleanupScanner(
        environment: CleanupScanner.Environment(
            home: home,
            config: config,
            toolOutput: { tool, arguments in
                tools[([tool] + arguments).joined(separator: " ")]
            }
        )
    )
}

@Test func emptyHomeYieldsNoCandidates() throws {
    let home = Fixture.tempDir()
    defer { Fixture.remove(home) }

    let result = scanner(home: home).scan()

    #expect(result.candidates.isEmpty)
    #expect(result.auditOnly.isEmpty)
    #expect(result.excluded.isEmpty)
    #expect(result.totalEstimatedBytes == 0)
}

@Test func measuresDirectDeleteCandidatesFromFixtureTrees() throws {
    let home = Fixture.tempDir()
    defer { Fixture.remove(home) }
    Fixture.makeDir(home + "/Library/Developer/Xcode/DerivedData/Proj-abc")
    Fixture.write(home + "/Library/Developer/Xcode/DerivedData/Proj-abc/index.db", bytes: 8192)
    Fixture.makeDir(home + "/.cargo/registry/cache/index")
    Fixture.write(home + "/.cargo/registry/cache/index/foo.crate", bytes: 4096)

    let result = scanner(home: home).scan()

    let ids = result.candidates.map(\.id)
    #expect(ids.contains("xcode-derived-data"))
    #expect(ids.contains("cargo-registry-cache"))
    #expect(!ids.contains("user-logs"), "empty targets are not candidates")

    let derived = try #require(result.candidates.first { $0.id == "xcode-derived-data" })
    #expect(derived.mode == .directDelete)
    #expect(derived.estimatedBytes >= 8192, "estimate is the measured on-disk size")
    #expect(derived.risk == .low)
    #expect(derived.action == .deletePaths([home + "/Library/Developer/Xcode/DerivedData"]))
}

@Test func candidatesAreSortedLargestEstimateFirst() throws {
    let home = Fixture.tempDir()
    defer { Fixture.remove(home) }
    Fixture.makeDir(home + "/Library/Developer/Xcode/DerivedData")
    Fixture.write(home + "/Library/Developer/Xcode/DerivedData/small", bytes: 4096)
    Fixture.makeDir(home + "/Library/Logs")
    Fixture.write(home + "/Library/Logs/big.log", bytes: 65536)

    let result = scanner(home: home).scan()

    #expect(result.candidates.map(\.id) == ["user-logs", "xcode-derived-data"])
}

@Test func brewCandidateParsesTheToolsOwnDryRun() throws {
    let home = Fixture.tempDir()
    defer { Fixture.remove(home) }

    let dryRun = """
    Would remove: /Users/x/Library/Caches/Homebrew/node--22.1.tgz (48.2MB)
    Would remove: /opt/homebrew/Cellar/git/2.43.0 (83.5MB)
    This operation would free approximately 131.7MB of disk space.
    """
    let result = scanner(home: home, tools: ["brew cleanup --dry-run": dryRun]).scan()

    let brew = try #require(result.candidates.first { $0.id == "brew-cleanup" })
    #expect(brew.mode == .officialCommand)
    #expect(brew.estimatedBytes == UInt64(131.7 * 1024 * 1024))
    #expect(brew.estimateBasis.contains("2 items"))
    #expect(brew.action == .command(tool: "brew", arguments: ["cleanup"]))
}

@Test func brewDryRunFallsBackToSummingItemSizes() {
    let parsed = CleanupScanner.parseBrewDryRun(
        """
        Would remove: /a/thing.tgz (1.0MB)
        Would remove: /b/other.tgz (512KB)
        """
    )
    #expect(parsed.itemCount == 2)
    #expect(parsed.bytes == 1024 * 1024 + 512 * 1024)
}

@Test func brewWithNothingToCleanYieldsNoCandidate() {
    let home = Fixture.tempDir()
    defer { Fixture.remove(home) }

    let result = scanner(home: home, tools: ["brew cleanup --dry-run": ""]).scan()
    #expect(!result.candidates.contains { $0.id == "brew-cleanup" })
}

@Test func missingToolsYieldNoOfficialCommandCandidates() {
    let home = Fixture.tempDir()
    defer { Fixture.remove(home) }

    let result = scanner(home: home).scan()
    #expect(!result.candidates.contains { $0.mode == .officialCommand })
}

@Test func npmCandidateMeasuresTheStoreReportedByNpm() throws {
    let home = Fixture.tempDir()
    defer { Fixture.remove(home) }
    Fixture.makeDir(home + "/.npm/_cacache")
    Fixture.write(home + "/.npm/_cacache/blob", bytes: 16384)

    let result = scanner(home: home, tools: ["npm config get cache": home + "/.npm"]).scan()

    let npm = try #require(result.candidates.first { $0.id == "npm-cache" })
    #expect(npm.mode == .officialCommand)
    #expect(npm.estimatedBytes >= 16384)
    #expect(npm.confidence == .high)
}

@Test func pnpmStoreStatesPruneGranularityInsteadOfFakingIt() throws {
    let home = Fixture.tempDir()
    defer { Fixture.remove(home) }
    Fixture.makeDir(home + "/store/v3")
    Fixture.write(home + "/store/v3/pkg", bytes: 4096)

    let result = scanner(home: home, tools: ["pnpm store path": home + "/store"]).scan()

    let pnpm = try #require(result.candidates.first { $0.id == "pnpm-store" })
    #expect(pnpm.estimateBasis.contains("unreferenced"))
    #expect(pnpm.confidence == .medium)
}

@Test func unavailableSimulatorsCandidateCountsDevicesAndEstimatesZero() throws {
    let home = Fixture.tempDir()
    defer { Fixture.remove(home) }

    let listing = """
    == Devices ==
    -- iOS 16.4 --
    -- Unavailable: com.apple.CoreSimulator.SimRuntime.iOS-15-0 --
        iPhone 8 (ABC) (Shutdown) (unavailable, runtime profile not found)
        iPhone X (DEF) (Shutdown) (unavailable, runtime profile not found)
    """
    let result = scanner(home: home, tools: ["xcrun simctl list devices unavailable": listing]).scan()

    let sims = try #require(result.candidates.first { $0.id == "simctl-unavailable" })
    #expect(sims.title.contains("(2)"))
    #expect(sims.estimatedBytes == 0)
    #expect(sims.confidence == .low)
}

@Test func noUnavailableSimulatorsYieldsNoCandidate() {
    let home = Fixture.tempDir()
    defer { Fixture.remove(home) }

    let listing = """
    == Devices ==
    -- iOS 16.4 --
    """
    let result = scanner(home: home, tools: ["xcrun simctl list devices unavailable": listing]).scan()
    #expect(!result.candidates.contains { $0.id == "simctl-unavailable" })
}

@Test func configExclusionDropsCandidateAndRecordsThePath() throws {
    let home = Fixture.tempDir()
    defer { Fixture.remove(home) }
    let derivedData = home + "/Library/Developer/Xcode/DerivedData"
    Fixture.makeDir(derivedData)
    Fixture.write(derivedData + "/index.db", bytes: 8192)

    var config = ConfigFile.default
    config.excludePaths = [derivedData]

    let result = scanner(home: home, config: config).scan()

    #expect(!result.candidates.contains { $0.id == "xcode-derived-data" })
    #expect(result.excluded == [derivedData])
}

@Test func versionManagersAreAuditOnlyNeverCandidates() throws {
    let home = Fixture.tempDir()
    defer { Fixture.remove(home) }
    Fixture.makeDir(home + "/.nvm/versions/node/v22.1.0")
    Fixture.write(home + "/.nvm/versions/node/v22.1.0/bin", bytes: 32768)
    Fixture.makeDir(home + "/.rustup/toolchains/stable")
    Fixture.write(home + "/.rustup/toolchains/stable/rustc", bytes: 4096)

    let result = scanner(home: home).scan()

    #expect(result.candidates.isEmpty)
    let titles = result.auditOnly.map(\.title)
    #expect(titles.contains("nvm Node versions"))
    #expect(titles.contains("rustup toolchains"))
    #expect(result.auditOnly.first?.title == "nvm Node versions", "audit-only findings sort largest first")
}

@Test func parseHumanSizeHandlesBrewUnits() {
    #expect(CleanupScanner.parseHumanSize(in: "804KB") == 804 * 1024)
    #expect(CleanupScanner.parseHumanSize(in: "approximately 1.5GB of disk") == UInt64(1.5 * 1024 * 1024 * 1024))
    #expect(CleanupScanner.parseHumanSize(in: "123B") == 123)
    #expect(CleanupScanner.parseHumanSize(in: "no size here") == nil)
}
