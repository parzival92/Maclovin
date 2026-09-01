import ArgumentParser
import MaclovinCore

struct AppsAuditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Explain application bundles and related application data."
    )

    @Option(name: .long, help: "Number of largest apps to list.")
    var top: Int = 15

    func run() throws {
        let report = AppsAuditor.audit()

        var sections: [ReportSection] = [
            ReportSection(
                title: "Summary",
                rows: [
                    ReportRow("Apps", "\(report.footprints.count)"),
                    ReportRow("Total (apps + data)", ByteSize(report.totalBytes).formatted),
                    ReportRow("Attributed to apps", ByteSize(report.attributedBytes).formatted),
                    ReportRow("Unattributed data", ByteSize(report.unattributedBytes).formatted),
                    ReportRow("Scanned", report.scannedDirectories.isEmpty ? "none" : report.scannedDirectories.joined(separator: ", ")),
                    ReportRow("Writes", "none")
                ]
            )
        ]

        if report.footprints.isEmpty {
            sections.append(ReportSection(title: "Largest Apps", rows: [ReportRow("(none found)", "")]))
        } else {
            let listed = Array(report.footprints.prefix(max(0, top)))
            let total = Double(report.totalBytes)
            let sizeWidth = listed.map { $0.totalSize.formatted.count }.max() ?? 0

            // One line per app: with fifteen rows by default, the breakdown
            // earns its place on the row rather than on a line of its own.
            let rows = listed.map { footprint -> ReportRow in
                let share = total > 0 ? Double(footprint.totalBytes) / total : 0
                let breakdown: String
                if footprint.dataBytes > 0 {
                    let confidence = footprint.dataConfidence
                        .map { " · \($0.label.lowercased())-confidence match" } ?? ""
                    breakdown = "bundle \(footprint.bundleSize.formatted) + data \(footprint.dataSize.formatted)\(confidence)"
                } else {
                    breakdown = "bundle only; no data matched"
                }
                let value = [
                    TerminalStyle.padLeading(footprint.totalSize.formatted, to: sizeWidth),
                    TerminalStyle.padLeading(String(format: "%.0f%%", share * 100), to: 4),
                    breakdown
                ].joined(separator: "  ")
                return ReportRow(footprint.name, value)
            }
            sections.append(ReportSection(title: "Largest Apps", rows: rows))
        }

        if !report.unattributed.isEmpty {
            sections.append(
                ReportSection(
                    title: "Unattributed Data (by location)",
                    rows: report.unattributed.map { ReportRow($0.source.rawValue, $0.size.formatted) }
                )
            )

            let largestItems = report.unattributed
                .flatMap(\.largest)
                .sorted { $0.size > $1.size }
                .prefix(5)
            if !largestItems.isEmpty {
                sections.append(
                    ReportSection(
                        title: "Largest Unattributed Folders",
                        rows: {
                            let width = largestItems.map { $0.size.formatted.count }.max() ?? 0
                            return largestItems.map {
                                ReportRow(
                                    $0.folderName,
                                    "\(TerminalStyle.padLeading($0.size.formatted, to: width))  in \($0.source.rawValue)"
                                )
                            }
                        }()
                    )
                )
            }
        }

        if !report.skippedDirectories.isEmpty {
            sections.append(
                ReportSection(
                    title: "Skipped",
                    rows: report.skippedDirectories.map { ReportRow($0, "absent or unreadable") }
                )
            )
        }

        let footer = [
            "Sizes are on-disk allocated bytes. Hardlinks counted once; symlinks not followed.",
            "Data is matched to apps by bundle ID (high) or name (medium); unmatched data is listed separately.",
            "These numbers are Maclovin's own measurement and do not reproduce macOS Storage Settings.",
            "Percentages are each app's share of the total above."
        ]

        print(ReportPrinter.render(title: "Applications Audit", sections: sections, footer: footer))
    }
}
