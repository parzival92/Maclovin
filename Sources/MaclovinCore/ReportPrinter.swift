import Foundation

public struct ReportSection: Equatable, Sendable {
    public let title: String
    public let rows: [ReportRow]

    public init(title: String, rows: [ReportRow]) {
        self.title = title
        self.rows = rows
    }
}

public struct ReportRow: Equatable, Sendable {
    public let label: String
    public let value: String
    /// Optional explanation, printed under the value in a quieter style.
    /// Newlines start a new note line rather than reflowing into one paragraph.
    public let note: String?

    public init(_ label: String, _ value: String, note: String? = nil) {
        self.label = label
        self.value = value
        self.note = note
    }
}

/// Renders reports as aligned, wrapped, terminal-width text.
///
/// Labels in a section share a column so values can be scanned vertically, and
/// every long string is wrapped with a hanging indent instead of relying on the
/// terminal to fold it at an arbitrary point.
public enum ReportPrinter {
    static let indent = "  "
    /// Past this, a label stops earning its column and gets its own line.
    static let maximumLabelWidth = 30
    static let labelValueGap = 2

    public static func render(
        title: String,
        sections: [ReportSection],
        footer: [String] = [],
        lead: [String] = []
    ) -> String {
        let width = TerminalStyle.width
        var lines: [String] = [TerminalStyle.bold(title), String(repeating: "=", count: title.count)]

        for paragraph in lead where !paragraph.isEmpty {
            lines.append("")
            lines.append(contentsOf: TerminalStyle.wrapText(paragraph, width: width))
        }

        for section in sections {
            lines.append("")
            lines.append(TerminalStyle.bold(section.title))
            lines.append(TerminalStyle.dim(String(repeating: "-", count: section.title.count)))
            lines.append(contentsOf: renderRows(section.rows, width: width))
        }

        if !footer.isEmpty {
            lines.append("")
            lines.append(TerminalStyle.bold("Notes"))
            lines.append(TerminalStyle.dim(String(repeating: "-", count: 5)))
            for entry in footer {
                let wrapped = TerminalStyle.wrapText(entry, width: width - indent.count - 2)
                for (offset, line) in wrapped.enumerated() {
                    lines.append(offset == 0 ? "\(indent)- \(line)" : "\(indent)  \(line)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    static func renderRows(_ rows: [ReportRow], width: Int) -> [String] {
        let labelWidth = rows
            .filter { !$0.value.isEmpty }
            .map { TerminalStyle.visibleLength($0.label) }
            .filter { $0 <= maximumLabelWidth }
            .max() ?? 0
        let valueColumn = indent.count + labelWidth + labelValueGap
        var lines: [String] = []

        for row in rows {
            lines.append(contentsOf: renderRow(row, labelWidth: labelWidth, valueColumn: valueColumn, width: width))
        }
        return lines
    }

    static func renderRow(_ row: ReportRow, labelWidth: Int, valueColumn: Int, width: Int) -> [String] {
        var lines: [String] = []
        let continuation = String(repeating: " ", count: valueColumn)

        if row.label.isEmpty, row.value.isEmpty {
            lines.append("")
        } else if row.value.isEmpty {
            lines.append(contentsOf: TerminalStyle.wrapText(row.label, width: width - indent.count).map { indent + $0 })
        } else if TerminalStyle.visibleLength(row.label) > labelWidth {
            // An over-long label keeps its own line so the value column stays honest.
            lines.append(indent + row.label)
            lines.append(contentsOf: TerminalStyle.wrapText(row.value, width: width - valueColumn).map { continuation + $0 })
        } else {
            let wrapped = TerminalStyle.wrapText(row.value, width: width - valueColumn)
            let head = indent + TerminalStyle.pad(row.label, to: labelWidth) + String(repeating: " ", count: labelValueGap)
            lines.append(head + wrapped[0])
            lines.append(contentsOf: wrapped.dropFirst().map { continuation + $0 })
        }

        if let note = row.note, !note.isEmpty {
            for paragraph in note.split(separator: "\n", omittingEmptySubsequences: false) {
                lines.append(
                    contentsOf: TerminalStyle.wrapText(String(paragraph), width: width - valueColumn)
                        .map { continuation + TerminalStyle.dim($0) }
                )
            }
        }
        return lines
    }
}
