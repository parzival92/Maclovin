import MaclovinCore
import XCTest

final class ByteSizeTests: XCTestCase {
    func testFormatsBytes() {
        XCTAssertEqual(ByteSize(0).formatted, "0 B")
        XCTAssertEqual(ByteSize(42).formatted, "42 B")
        XCTAssertEqual(ByteSize(1023).formatted, "1023 B")
    }

    func testFormatsLargerUnits() {
        XCTAssertEqual(ByteSize(1024).formatted, "1.0 KB")
        XCTAssertEqual(ByteSize(10 * 1024).formatted, "10 KB")
        XCTAssertEqual(ByteSize(5 * 1024 * 1024).formatted, "5.0 MB")
        XCTAssertEqual(ByteSize(42 * 1024 * 1024 * 1024).formatted, "42 GB")
    }

    func testComparable() {
        XCTAssertLessThan(ByteSize(1), ByteSize(2))
    }
}
