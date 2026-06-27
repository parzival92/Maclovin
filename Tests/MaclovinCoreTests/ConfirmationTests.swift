import MaclovinCore
import Testing

@Test
func typedTargetMatchesExactInput() {
    #expect(Confirmation.evaluate(.typedTarget("Slack"), input: "Slack") == .confirmed)
}

@Test
func typedTargetTrimsSurroundingWhitespace() {
    #expect(Confirmation.evaluate(.typedTarget("Slack"), input: "  Slack\n") == .confirmed)
}

@Test
func typedTargetIsCaseSensitive() {
    #expect(Confirmation.evaluate(.typedTarget("Slack"), input: "slack") == .declined)
}

@Test
func typedTargetRejectsWrongTarget() {
    #expect(Confirmation.evaluate(.typedTarget("Slack"), input: "Spotify") == .declined)
}

@Test
func typedTargetRejectsEmptyAndNilInput() {
    #expect(Confirmation.evaluate(.typedTarget("Slack"), input: "") == .declined)
    #expect(Confirmation.evaluate(.typedTarget("Slack"), input: nil) == .declined)
}

@Test
func cleanupBatchConfirmsOnApplyKeyword() {
    #expect(Confirmation.evaluate(.typedTarget("apply"), input: "apply") == .confirmed)
    #expect(Confirmation.evaluate(.typedTarget("apply"), input: "yes") == .declined)
}

@Test
func yesNoAcceptsAffirmativeAnswers() {
    #expect(Confirmation.evaluate(.yesNo, input: "y") == .confirmed)
    #expect(Confirmation.evaluate(.yesNo, input: "Y") == .confirmed)
    #expect(Confirmation.evaluate(.yesNo, input: "yes") == .confirmed)
    #expect(Confirmation.evaluate(.yesNo, input: "YES") == .confirmed)
}

@Test
func yesNoDefaultsToNoOnEmptyOrUnrecognizedInput() {
    #expect(Confirmation.evaluate(.yesNo, input: "") == .declined)
    #expect(Confirmation.evaluate(.yesNo, input: nil) == .declined)
    #expect(Confirmation.evaluate(.yesNo, input: "n") == .declined)
    #expect(Confirmation.evaluate(.yesNo, input: "maybe") == .declined)
}

@Test
func promptLineDescribesTypedTarget() {
    #expect(Confirmation.promptLine(.typedTarget("Slack"), action: "uninstall") == "Type 'Slack' to confirm uninstall: ")
    #expect(Confirmation.promptLine(.yesNo, action: "uninstall") == "Confirm uninstall? [y/N]: ")
}
