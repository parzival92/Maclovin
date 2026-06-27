public enum Risk: String, CaseIterable, Sendable {
    case low
    case medium
    case high

    public var label: String {
        switch self {
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        }
    }

    public var explanation: String {
        switch self {
        case .low:
            "Generated data or official cleanup path."
        case .medium:
            "Usually recoverable, but worth reviewing."
        case .high:
            "May remove user state, projects, or runtime dependencies."
        }
    }
}
