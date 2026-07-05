import MaclovinCore
import Testing

@Test
func missingKeysFallBackToDefaults() {
    let config = ConfigFile.parse("")
    #expect(config == .default)
    #expect(config.requireTypedConfirmation)
    #expect(config.moveAppDataToTrash)
    #expect(config.historyEnabled)
    #expect(config.excludePaths.isEmpty)
}

@Test
func parsesDocumentedExampleConfig() {
    let text = """
    [scan]
    deep_scan_default = false
    exclude_paths = [
      "~/Library/Application Support/ImportantApp",
      "~/Work"
    ]

    [cleanup]
    require_typed_confirmation = true
    move_app_data_to_trash = true

    [history]
    enabled = true
    """
    let config = ConfigFile.parse(text)
    #expect(config.excludePaths == ["~/Library/Application Support/ImportantApp", "~/Work"])
    #expect(config.requireTypedConfirmation)
    #expect(config.moveAppDataToTrash)
    #expect(config.historyEnabled)
}

@Test
func parsesFalseBooleansAndSingleLineArray() {
    let text = """
    [scan]
    exclude_paths = ["~/Work"]
    [cleanup]
    require_typed_confirmation = false
    move_app_data_to_trash = false
    [history]
    enabled = false
    """
    let config = ConfigFile.parse(text)
    #expect(config.excludePaths == ["~/Work"])
    #expect(!config.requireTypedConfirmation)
    #expect(!config.moveAppDataToTrash)
    #expect(!config.historyEnabled)
}

@Test
func ignoresCommentsAndUnknownKeys() {
    let text = """
    # top-level comment
    [cleanup]
    require_typed_confirmation = false  # lighter gate
    some_future_key = true
    [scan]
    exclude_paths = ["~/has # hash"]  # comment after array
    """
    let config = ConfigFile.parse(text)
    #expect(!config.requireTypedConfirmation)
    #expect(config.excludePaths == ["~/has # hash"])
}

@Test
func invalidBooleanKeepsDefault() {
    let config = ConfigFile.parse("[history]\nenabled = maybe")
    #expect(config.historyEnabled)
}

@Test
func gateStyleFollowsTypedConfirmationSetting() {
    var config = ConfigFile.default
    #expect(config.gate(typedTarget: "Slack") == .typedTarget("Slack"))
    config.requireTypedConfirmation = false
    #expect(config.gate(typedTarget: "Slack") == .yesNo)
}

@Test
func exclusionMatchesPathAndSubpaths() {
    let config = ConfigFile(
        excludePaths: ["~/Work"],
        requireTypedConfirmation: true,
        moveAppDataToTrash: true,
        historyEnabled: true
    )
    let home = MaclovinPaths.homeDirectory.path
    #expect(config.isExcluded(home + "/Work"))
    #expect(config.isExcluded(home + "/Work/project"))
    #expect(!config.isExcluded(home + "/Workspace"))
}
