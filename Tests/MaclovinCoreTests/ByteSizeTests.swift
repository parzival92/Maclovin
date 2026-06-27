import MaclovinCore
import Testing

@Test
func byteSizeFormatsBytes() {
    #expect(ByteSize(0).formatted == "0 B")
    #expect(ByteSize(42).formatted == "42 B")
    #expect(ByteSize(1023).formatted == "1023 B")
}

@Test
func byteSizeFormatsLargerUnits() {
    #expect(ByteSize(1024).formatted == "1.0 KB")
    #expect(ByteSize(10 * 1024).formatted == "10 KB")
    #expect(ByteSize(5 * 1024 * 1024).formatted == "5.0 MB")
    #expect(ByteSize(42 * 1024 * 1024 * 1024).formatted == "42 GB")
}

@Test
func byteSizeIsComparable() {
    #expect(ByteSize(1) < ByteSize(2))
}
