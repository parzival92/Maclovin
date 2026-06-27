import MaclovinCore
import Testing

@Test
func reportPrinterRendersSectionsAndFooter() {
    let output = ReportPrinter.render(
        title: "Title",
        sections: [
            ReportSection(
                title: "Section",
                rows: [
                    ReportRow("Key", "Value")
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
            Key: Value

            Footer
            """
    )
}
