import ArgumentParser

enum ExecutionMode: String, EnumerableFlag {
    case dryRun
    case apply

    var label: String {
        switch self {
        case .dryRun:
            "dry-run"
        case .apply:
            "apply"
        }
    }
}
