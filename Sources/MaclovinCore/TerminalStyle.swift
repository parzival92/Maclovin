import Foundation

/// ANSI styling and terminal geometry for human-facing output.
///
/// Everything degrades to plain text: styling is applied only when stdout is a
/// terminal that has not asked to be left alone, so piped and redirected output
/// stays free of escape sequences.
public enum TerminalStyle {
    /// Widest line the renderer will produce. Wide terminals are not filled
    /// edge to edge, because long unbroken lines are what make reports hard to
    /// read in the first place.
    static let maximumWidth = 96
    static let minimumWidth = 48
    static let fallbackWidth = 88

    public static let isColorEnabled: Bool = {
        let environment = ProcessInfo.processInfo.environment
        if environment["NO_COLOR"] != nil { return false }
        if environment["TERM"] == "dumb" || environment["TERM"] == nil { return false }
        return isatty(STDOUT_FILENO) == 1
    }()

    /// Usable line width, honouring `COLUMNS` before asking the terminal.
    public static var width: Int {
        if let columns = ProcessInfo.processInfo.environment["COLUMNS"], let value = Int(columns), value > 0 {
            return clamp(value)
        }
        var size = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0, size.ws_col > 0 {
            return clamp(Int(size.ws_col))
        }
        return fallbackWidth
    }

    static func clamp(_ value: Int) -> Int {
        max(minimumWidth, min(maximumWidth, value))
    }

    // MARK: - Attributes

    public static func bold(_ text: String) -> String { wrap(text, "1") }
    public static func dim(_ text: String) -> String { wrap(text, "2") }
    public static func red(_ text: String) -> String { wrap(text, "31") }
    public static func yellow(_ text: String) -> String { wrap(text, "33") }
    public static func green(_ text: String) -> String { wrap(text, "32") }
    public static func cyan(_ text: String) -> String { wrap(text, "36") }

    static func wrap(_ text: String, _ code: String) -> String {
        guard isColorEnabled, !text.isEmpty else { return text }
        return "\u{1B}[\(code)m\(text)\u{1B}[0m"
    }

    /// Length as the terminal sees it, ignoring escape sequences.
    public static func visibleLength(_ text: String) -> Int {
        var length = 0
        var inEscape = false
        for character in text {
            if inEscape {
                if character == "m" { inEscape = false }
                continue
            }
            if character == "\u{1B}" {
                inEscape = true
                continue
            }
            length += 1
        }
        return length
    }

    /// Pads to `width` counting only visible characters.
    public static func pad(_ text: String, to width: Int) -> String {
        let padding = width - visibleLength(text)
        return padding > 0 ? text + String(repeating: " ", count: padding) : text
    }

    /// Right-aligns to `width` counting only visible characters.
    public static func padLeading(_ text: String, to width: Int) -> String {
        let padding = width - visibleLength(text)
        return padding > 0 ? String(repeating: " ", count: padding) + text : text
    }

    /// A proportional bar, sized against the largest value in the same list, so
    /// a ranked table can be read at a glance without doing the arithmetic.
    ///
    /// Any non-zero value gets at least one block: a row that is present should
    /// never render as nothing.
    public static func bar(_ value: Double, of largest: Double, width: Int = 12) -> String {
        guard largest > 0, value > 0 else { return "" }
        let filled = max(1, Int((value / largest * Double(width)).rounded()))
        return String(repeating: "#", count: min(width, filled))
    }

    /// Greedy word wrap. Words longer than the limit are left intact rather
    /// than broken, so paths and identifiers stay copy-pasteable.
    ///
    /// Runs of spaces inside a line are preserved, because they are usually
    /// column padding: a wrapped row must not lose the alignment of the rows
    /// above it. Text that already fits is returned untouched.
    public static func wrapText(_ text: String, width: Int) -> [String] {
        let limit = max(20, width)
        guard visibleLength(text) > limit else { return [text] }

        var lines: [String] = []
        var current = ""
        var gap = ""
        var word = ""

        func flushWord() {
            guard !word.isEmpty else { return }
            let candidate = current.isEmpty ? word : current + gap + word
            if current.isEmpty || visibleLength(candidate) <= limit {
                current = candidate
            } else {
                lines.append(current)
                current = word
            }
            gap = ""
            word = ""
        }

        for character in text {
            if character == " " {
                flushWord()
                gap.append(character)
            } else {
                word.append(character)
            }
        }
        flushWord()

        if !current.isEmpty { lines.append(current) }
        return lines.isEmpty ? [""] : lines
    }
}
