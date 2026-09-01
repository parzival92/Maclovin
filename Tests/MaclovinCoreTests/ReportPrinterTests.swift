import MaclovinCore
import Testing

@Test
func reportPrinterAlignsLabelsAndRendersFooterAsNotes() {
    let output = ReportPrinter.render(
        title: "Title",
        sections: [
            ReportSection(
                title: "Section",
                rows: [
                    ReportRow("Key", "Value"),
                    ReportRow("Longer key", "Other")
                ]
            )
        ],
        footer: ["Footer"]
    )

    #expect(
        output ==
            """
            Title
            =====

            Section
            -------
              Key         Value
              Longer key  Other

            Notes
            -----
              - Footer
            """
    )
}

@Test
func reportPrinterRendersLeadNoteAndEmptyRow() {
    let output = ReportPrinter.render(
        title: "T",
        sections: [
            ReportSection(
                title: "S",
                rows: [
                    ReportRow("Key", "Value", note: "why it matters"),
                    ReportRow("", ""),
                    ReportRow("(nothing found)", "")
                ]
            )
        ],
        lead: ["A one-line verdict."]
    )

    #expect(
        output ==
            """
            T
            =

            A one-line verdict.

            S
            -
              Key  Value
                   why it matters

              (nothing found)
            """
    )
}

@Test
func wrapTextLeavesFittingTextUntouched() {
    // Pre-aligned columns must survive: only wrapping collapses spacing.
    #expect(TerminalStyle.wrapText("a    b", width: 40) == ["a    b"])
}

@Test
func wrapTextBreaksOnWordBoundaries() {
    #expect(TerminalStyle.wrapText("alpha beta gamma", width: 20) == ["alpha beta gamma"])
    #expect(TerminalStyle.wrapText(String(repeating: "word ", count: 8), width: 20).count > 1)
}

@Test
func visibleLengthIgnoresEscapeSequences() {
    #expect(TerminalStyle.visibleLength("\u{1B}[1mbold\u{1B}[0m") == 4)
    #expect(TerminalStyle.pad("ab", to: 5) == "ab   ")
    #expect(TerminalStyle.padLeading("ab", to: 5) == "   ab")
}

@Test
func wrapPreservesColumnPaddingOnTheLineItKeeps() {
    // A wrapped row must not lose the alignment of the rows above it.
    let wrapped = TerminalStyle.wrapText("850 MB   1%  a long trailing description here", width: 30)
    #expect(wrapped.count == 2)
    #expect(wrapped[0].hasPrefix("850 MB   1%  "))
}

@Test
func notesSplitOnNewlinesInsteadOfReflowing() {
    let output = ReportPrinter.render(
        title: "T",
        sections: [ReportSection(title: "S", rows: [ReportRow("K", "V", note: "first\nsecond")])]
    )
    #expect(output.hasSuffix("  K  V\n     first\n     second"))
}

@Test
func barIsProportionalAndNeverEmptyForAPresentValue() {
    #expect(TerminalStyle.bar(100, of: 100, width: 10) == String(repeating: "#", count: 10))
    #expect(TerminalStyle.bar(1, of: 1000, width: 10) == "#")
    #expect(TerminalStyle.bar(0, of: 1000, width: 10) == "")
    #expect(TerminalStyle.bar(5, of: 0, width: 10) == "")
}

@Test
func pluralCountAgreesWithItsNumber() {
    #expect(Plural.count(1, "candidate") == "1 candidate")
    #expect(Plural.count(0, "candidate") == "0 candidates")
    #expect(Plural.count(2, "entry", "entries") == "2 entries")
}
