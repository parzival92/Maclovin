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
            let rows = report.footprints.prefix(max(0, top)).map { footprint -> ReportRow in
                let value: String
                if footprint.dataBytes > 0 {
                    let confidence = footprint.dataConfidence.map { " [\($0.label)]" } ?? ""
                    value = "\(footprint.totalSize.formatted)  (bundle \(footprint.bundleSize.formatted) + data \(footprint.dataSize.formatted)\(confidence))"
                } else {
                    value = "\(footprint.totalSize.formatted)  (bundle only)"
                }
                return ReportRow(footprint.name, value)
            }
            sections.append(ReportSection(title: "Largest Apps", rows: rows))
        }

        if !report.unattributed.isEmpty {
            var rows = report.unattributed.map { bucket in
                ReportRow(bucket.source.rawValue, bucket.size.formatted)
            }
            let largestItems = report.unattributed
                .flatMap(\.largest)
                .sorted { $0.size > $1.size }
                .prefix(5)
            for item in largestItems {
                rows.append(ReportRow("• \(item.folderName)", "\(item.size.formatted) (\(item.source.rawValue))"))
            }
            sections.append(ReportSection(title: "Unattributed Data", rows: rows))
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
            "These numbers are Maclovin's own measurement and do not reproduce macOS Storage Settings."
        ]

        print(ReportPrinter.render(title: "Applications Audit", sections: sections, footer: footer))
    }
}
