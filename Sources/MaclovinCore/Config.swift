import Foundation

/// Maclovin's minimal local configuration, read from
/// `~/.config/maclovin/config.toml`.
///
/// Only the documented keys are recognized; unknown keys are ignored so a
/// hand-edited file never breaks a scan. Every field has a safe default and a
/// missing or unparsable file simply yields ``ConfigFile/default``.
public struct ConfigFile: Equatable, Sendable {
    /// `[scan] exclude_paths` — paths (tilde-expandable) never measured or
    /// offered as cleanup candidates.
    public var excludePaths: [String]
    /// `[cleanup] require_typed_confirmation` — when false, destructive gates
    /// fall back to `[y/N]` (never zero-interaction).
    public var requireTypedConfirmation: Bool
    /// `[cleanup] move_app_data_to_trash` — related app data goes to Trash
    /// rather than being permanently deleted.
    public var moveAppDataToTrash: Bool
    /// `[history] enabled` — whether scans and actions write local history.
    public var historyEnabled: Bool

    public static let `default` = ConfigFile(
        excludePaths: [],
        requireTypedConfirmation: true,
        moveAppDataToTrash: true,
        historyEnabled: true
    )

    public init(
        excludePaths: [String],
        requireTypedConfirmation: Bool,
        moveAppDataToTrash: Bool,
        historyEnabled: Bool
    ) {
        self.excludePaths = excludePaths
        self.requireTypedConfirmation = requireTypedConfirmation
        self.moveAppDataToTrash = moveAppDataToTrash
        self.historyEnabled = historyEnabled
    }

    /// The confirmation gate style implied by this config for a given typed
    /// target (see PRD "Confirmation Gate").
    public func gate(typedTarget: String) -> ConfirmationGate {
        requireTypedConfirmation ? .typedTarget(typedTarget) : .yesNo
    }

    /// Exclude paths with `~` expanded, for direct comparison against
    /// absolute measurement targets.
    public var expandedExcludePaths: [String] {
        excludePaths.map { MaclovinPaths.expandTilde(in: $0) }
    }

    /// True when `path` is inside (or is) one of the configured exclusions.
    public func isExcluded(_ path: String) -> Bool {
        expandedExcludePaths.contains { excluded in
            path == excluded || path.hasPrefix(excluded + "/")
        }
    }

    /// Loads the config from the default location, falling back to defaults
    /// when the file is missing.
    public static func load() -> ConfigFile {
        guard let text = try? String(contentsOf: MaclovinPaths.configFile, encoding: .utf8) else {
            return .default
        }
        return parse(text)
    }

    /// Parses the minimal TOML subset Maclovin documents: `[section]` headers,
    /// `key = value` with booleans, quoted strings, and (possibly multi-line)
    /// string arrays. Comments start with `#`.
    public static func parse(_ text: String) -> ConfigFile {
        var config = ConfigFile.default
        var section = ""
        // Multi-line arrays are accumulated until the closing bracket.
        var pendingKey: String?
        var pendingArray = ""

        func assign(section: String, key: String, rawValue: String) {
            let value = rawValue.trimmingCharacters(in: .whitespaces)
            switch (section, key) {
            case ("scan", "exclude_paths"):
                config.excludePaths = parseStringArray(value)
            case ("cleanup", "require_typed_confirmation"):
                config.requireTypedConfirmation = parseBool(value) ?? config.requireTypedConfirmation
            case ("cleanup", "move_app_data_to_trash"):
                config.moveAppDataToTrash = parseBool(value) ?? config.moveAppDataToTrash
            case ("history", "enabled"):
                config.historyEnabled = parseBool(value) ?? config.historyEnabled
            default:
                break
            }
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)

            if let key = pendingKey {
                pendingArray += " " + line
                if line.contains("]") {
                    assign(section: section, key: key, rawValue: pendingArray)
                    pendingKey = nil
                    pendingArray = ""
                }
                continue
            }

            guard !line.isEmpty else { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }

            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)

            if value.hasPrefix("["), !value.contains("]") {
                pendingKey = key
                pendingArray = value
            } else {
                assign(section: section, key: key, rawValue: value)
            }
        }

        return config
    }

    static func parseBool(_ value: String) -> Bool? {
        switch value {
        case "true": true
        case "false": false
        default: nil
        }
    }

    /// Parses `["a", "b"]` into its elements; tolerates trailing commas.
    static func parseStringArray(_ value: String) -> [String] {
        guard let open = value.firstIndex(of: "["), let close = value.lastIndex(of: "]") else {
            return []
        }
        let inner = value[value.index(after: open)..<close]
        return inner
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { unquote($0) }
    }

    static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    /// Removes a `#` comment, respecting `#` inside quoted strings.
    static func stripComment(_ line: String) -> String {
        var inDouble = false
        var inSingle = false
        for index in line.indices {
            switch line[index] {
            case "\"" where !inSingle: inDouble.toggle()
            case "'" where !inDouble: inSingle.toggle()
            case "#" where !inDouble && !inSingle:
                return String(line[..<index])
            default:
                break
            }
        }
        return line
    }
}
