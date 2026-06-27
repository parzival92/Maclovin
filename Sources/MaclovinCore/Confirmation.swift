import Foundation

/// The confirmation gate shown before any destructive cleanup or uninstall action.
///
/// Maclovin never deletes or moves files without a deliberate confirmation.
/// There are two gate styles:
///
/// - ``typedTarget(_:)`` requires the user to type an exact string: the resolved
///   app or formula name for an uninstall, or the literal word `apply` for a
///   cleanup batch. Typing the target name guards against acting on the *wrong*
///   thing, not just against a stray keystroke.
/// - ``yesNo`` is the lighter `[y/N]` fallback used when the user sets
///   `require_typed_confirmation = false` in config. It still always prompts —
///   Maclovin never performs a destructive action with zero interaction.
public enum ConfirmationGate: Equatable, Sendable {
    /// The user must type `expected` exactly to proceed. Matching is
    /// case-sensitive; surrounding whitespace is ignored.
    case typedTarget(String)
    /// A `[y/N]` prompt that defaults to "no" on empty or unrecognized input.
    case yesNo
}

/// The result of evaluating user input against a ``ConfirmationGate``.
public enum ConfirmationOutcome: Equatable, Sendable {
    /// Input matched the gate; the action may proceed.
    case confirmed
    /// Input did not match. The action aborts with no changes; Maclovin does
    /// not loop or re-prompt.
    case declined
}

public enum Confirmation {
    /// Evaluates raw user input against a gate.
    ///
    /// Pure and synchronous so it can be unit-tested without standard input.
    ///
    /// Matching rules:
    /// - Leading and trailing whitespace and newlines are trimmed from input.
    /// - ``ConfirmationGate/typedTarget(_:)`` requires a case-sensitive exact
    ///   match of the trimmed input against the expected string.
    /// - ``ConfirmationGate/yesNo`` accepts `y` or `yes` case-insensitively;
    ///   everything else, including empty or `nil` input, is declined.
    /// - Any mismatch is ``ConfirmationOutcome/declined``; callers abort rather
    ///   than re-prompt.
    public static func evaluate(_ gate: ConfirmationGate, input: String?) -> ConfirmationOutcome {
        let trimmed = (input ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch gate {
        case .typedTarget(let expected):
            return trimmed == expected ? .confirmed : .declined
        case .yesNo:
            switch trimmed.lowercased() {
            case "y", "yes":
                return .confirmed
            default:
                return .declined
            }
        }
    }

    /// The single-line instruction shown to the user, describing exactly what to
    /// type for the given gate and action (for example `apply` or
    /// `uninstall Slack`).
    public static func promptLine(_ gate: ConfirmationGate, action: String) -> String {
        switch gate {
        case .typedTarget(let expected):
            return "Type '\(expected)' to confirm \(action): "
        case .yesNo:
            return "Confirm \(action)? [y/N]: "
        }
    }
}
