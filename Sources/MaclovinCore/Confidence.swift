public enum Confidence: String, CaseIterable, Sendable {
    case high
    case medium
    case low

    public var label: String {
        switch self {
        case .high:
            "High"
        case .medium:
            "Medium"
        case .low:
            "Low"
        }
    }

    public var explanation: String {
        switch self {
        case .high:
            "Direct ownership evidence is available."
        case .medium:
            "Likely ownership evidence is available."
        case .low:
            "The relationship is a best-effort guess."
        }
    }
}
