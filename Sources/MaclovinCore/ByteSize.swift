import Foundation

public struct ByteSize: Equatable, Comparable, Sendable {
    public let bytes: UInt64

    public init(_ bytes: UInt64) {
        self.bytes = bytes
    }

    public static func < (lhs: ByteSize, rhs: ByteSize) -> Bool {
        lhs.bytes < rhs.bytes
    }

    public var formatted: String {
        formatted()
    }

    public func formatted(precision: Int = 1) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]

        if bytes < 1024 {
            return "\(bytes) B"
        }

        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        let resolvedPrecision = value >= 10 ? 0 : max(0, precision)
        return "\(String(format: "%.\(resolvedPrecision)f", value)) \(units[unitIndex])"
    }
}
