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

    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

public enum ReportPrinter {
    public static func render(
        title: String,
        sections: [ReportSection],
        footer: [String] = []
    ) -> String {
        var lines: [String] = [title, String(repeating: "=", count: title.count)]

        for section in sections {
            lines.append("")
            lines.append(section.title)
            lines.append(String(repeating: "-", count: section.title.count))

            for row in section.rows {
                lines.append("\(row.label): \(row.value)")
            }
        }

        if !footer.isEmpty {
            lines.append("")
            lines.append(contentsOf: footer)
        }

        return lines.joined(separator: "\n")
    }
}
