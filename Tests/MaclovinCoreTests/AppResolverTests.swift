import MaclovinCore
import Testing

private let installed: [InstalledApp] = [
    InstalledApp(name: "Slack", path: "/Applications/Slack.app", bundleID: "com.tinyspeck.slackmacgap"),
    InstalledApp(name: "Spotify", path: "/Applications/Spotify.app", bundleID: "com.spotify.client")
]

@Test
func resolvesExactDisplayName() {
    #expect(AppResolver.resolve("Slack", in: installed) == .resolved(installed[0]))
}

@Test
func resolvesCaseInsensitively() {
    #expect(AppResolver.resolve("slack", in: installed) == .resolved(installed[0]))
    #expect(AppResolver.resolve("SPOTIFY", in: installed) == .resolved(installed[1]))
}

@Test
func appSuffixIsOptional() {
    #expect(AppResolver.resolve("Slack.app", in: installed) == .resolved(installed[0]))
    #expect(AppResolver.resolve("slack.APP", in: installed) == .resolved(installed[0]))
}

@Test
func trimsSurroundingWhitespace() {
    #expect(AppResolver.resolve("  slack \n", in: installed) == .resolved(installed[0]))
}

@Test
func resolvesByBundleIdentifier() {
    #expect(AppResolver.resolve("com.spotify.client", in: installed) == .resolved(installed[1]))
    #expect(AppResolver.resolve("COM.TINYSPECK.SLACKMACGAP", in: installed) == .resolved(installed[0]))
}

@Test
func reportsNoMatch() {
    #expect(AppResolver.resolve("Discord", in: installed) == .notFound(query: "Discord"))
}

@Test
func reportsAmbiguousWhenSameNameInMultipleLocations() {
    let userSlack = InstalledApp(
        name: "Slack",
        path: "/Users/me/Applications/Slack.app",
        bundleID: "com.tinyspeck.slackmacgap"
    )
    let apps = installed + [userSlack]

    let result = AppResolver.resolve("slack", in: apps)
    // Candidates are sorted by path for a stable report.
    #expect(result == .ambiguous(query: "slack", candidates: [installed[0], userSlack]))
}

@Test
func bundleIdentifierMatchTakesPrecedenceOverName() {
    // An app whose display name collides with another app's bundle identifier
    // string still resolves the bundle-identifier owner first.
    let odd = InstalledApp(name: "com.spotify.client", path: "/Applications/Odd.app", bundleID: "com.example.odd")
    let apps = installed + [odd]
    #expect(AppResolver.resolve("com.spotify.client", in: apps) == .resolved(installed[1]))
}

@Test
func collapsesDuplicatePathsToSingleMatch() {
    // A bundle that satisfies a tier more than once (same path) is not ambiguous.
    let apps = [installed[0], installed[0]]
    #expect(AppResolver.resolve("slack", in: apps) == .resolved(installed[0]))
}
