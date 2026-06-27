import MaclovinCore
import XCTest

final class SafetyLabelTests: XCTestCase {
    func testRiskLabelsAreHumanReadable() {
        XCTAssertEqual(Risk.low.label, "Low")
        XCTAssertEqual(Risk.medium.label, "Medium")
        XCTAssertEqual(Risk.high.label, "High")
    }

    func testConfidenceLabelsAreHumanReadable() {
        XCTAssertEqual(Confidence.high.label, "High")
        XCTAssertEqual(Confidence.medium.label, "Medium")
        XCTAssertEqual(Confidence.low.label, "Low")
    }
}
