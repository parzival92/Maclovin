import MaclovinCore
import XCTest

final class ReportPrinterTests: XCTestCase {
    func testRendersReportWithSectionsAndFooter() {
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

        XCTAssertEqual(
            output,
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
}
