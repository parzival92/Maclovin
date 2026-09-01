import ArgumentParser
import MaclovinCore

struct MemoryAuditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Explain memory pressure, the largest consumers, and idle runtimes.",
        discussion: """
        Read-only. Maclovin never signals, stops, or kills a process; where \
        memory is reclaimable it names the command that would release it and \
        leaves running it to you.
        """
    )

    @Option(name: .long, help: "Number of largest consumers to list.")
    var top: Int = 10

    func run() throws {
        guard let sample = MemorySampler.sample() else {
            throw ValidationError("Could not read kernel memory statistics.")
        }
        let report = MemoryAuditor.audit(sample: sample)
        print(
            ReportPrinter.render(
                title: "Memory Audit",
                sections: sections(for: report),
                footer: footer,
                lead: [verdict(for: report)]
            )
        )
    }

    /// One plain sentence about the state of the machine, so the report can be
    /// understood without reading the tables underneath it.
    private func verdict(for report: MemoryAuditReport) -> String {
        let strained = report.signals.filter { $0.level > .normal }.map(\.name)
        var sentence: String

        switch report.level {
        case .normal:
            sentence = "\(styled("Normal pressure", report.level)) — memory is keeping up with the workload."
        case .elevated:
            sentence = "\(styled("Elevated pressure", report.level)) — the machine is working to fit its workload in RAM"
            sentence += strained.isEmpty ? "." : " (\(strained.joined(separator: ", ")))."
        case .critical:
            sentence = "\(styled("Critical pressure", report.level)) — the workload does not fit in RAM"
            sentence += strained.isEmpty ? "." : " (\(strained.joined(separator: ", ")))."
        }

        if report.reclaimableBytes > 0 {
            sentence += " Up to \(ByteSize(report.reclaimableBytes).formatted) can be freed by quitting runtimes that report no workload; see Virtualization Runtimes below."
        }
        return sentence
    }

    private func sections(for report: MemoryAuditReport) -> [ReportSection] {
        var sections = [summarySection(report), pressureSection(report)]

        if !report.runtimes.isEmpty {
            sections.append(runtimeSection(report))
        }
        sections.append(consumerSection(report))

        if let note = report.permissionNote {
            sections.append(ReportSection(title: "Measurement Gaps", rows: [ReportRow("Processes", note)]))
        }
        return sections
    }

    private func summarySection(_ report: MemoryAuditReport) -> ReportSection {
        let sample = report.sample
        var rows = [
            ReportRow("Physical memory", ByteSize(sample.physicalBytes).formatted),
            ReportRow("In use", "\(ByteSize(sample.usedBytes).formatted) (\(MemoryAuditor.percent(sample.usedFraction)) of physical)"),
            ReportRow("Wired (not reclaimable)", ByteSize(sample.wiredBytes).formatted),
            ReportRow("Pressure", styled(report.level.label, report.level))
        ]
        if report.reclaimableBytes > 0 {
            rows.append(
                ReportRow(
                    "Reclaimable now",
                    "up to \(ByteSize(report.reclaimableBytes).formatted)",
                    note: "from runtimes reporting no workload"
                )
            )
        }
        rows.append(ReportRow("Writes", "none"))
        return ReportSection(title: "Summary", rows: rows)
    }

    private func pressureSection(_ report: MemoryAuditReport) -> ReportSection {
        let rows = report.signals.map { signal in
            ReportRow(signal.name, "\(tag(signal.level))  \(signal.measured)", note: signal.explanation)
        }
        return ReportSection(title: "Pressure Signals", rows: rows)
    }

    private func runtimeSection(_ report: MemoryAuditReport) -> ReportSection {
        var rows: [ReportRow] = []
        for (offset, runtime) in report.runtimes.enumerated() {
            if offset > 0 { rows.append(ReportRow("", "")) }
            rows.append(
                ReportRow(
                    runtime.name,
                    "\(runtime.size.formatted) — \(runtime.workload.label) (\(runtime.confidence.label.lowercased()) confidence)"
                )
            )
            rows.append(ReportRow("  evidence", runtime.evidence))
            rows.append(ReportRow("  state", runtime.workload.detail))
            if let suggestion = runtime.suggestion {
                rows.append(ReportRow("  to release", suggestion))
            }
        }
        return ReportSection(title: "Virtualization Runtimes", rows: rows)
    }

    private func consumerSection(_ report: MemoryAuditReport) -> ReportSection {
        guard !report.consumers.isEmpty else {
            return ReportSection(title: "Largest Consumers", rows: [ReportRow("(none readable)", "")])
        }
        let listed = Array(report.consumers.prefix(max(0, top)))
        let physical = Double(report.sample.physicalBytes)
        let largest = Double(listed.first?.bytes ?? 0)
        let sizeWidth = listed.map { $0.size.formatted.count }.max() ?? 0

        let rows = listed.map { consumer -> ReportRow in
            let share = physical > 0 ? Double(consumer.bytes) / physical : 0
            let value = [
                TerminalStyle.padLeading(consumer.size.formatted, to: sizeWidth),
                TerminalStyle.padLeading(MemoryAuditor.percent(share), to: 4),
                TerminalStyle.bar(Double(consumer.bytes), of: largest)
            ].joined(separator: "  ")

            let label = consumer.processCount > 1
                ? "\(consumer.name) (\(consumer.processCount))"
                : consumer.name
            let note = consumer.basis == .resident ? "\(consumer.basis.label) — understates" : nil
            return ReportRow(label, value, note: note)
        }
        return ReportSection(title: "Largest Consumers", rows: rows)
    }


    private func tag(_ level: MemoryPressureLevel) -> String {
        styled(TerminalStyle.pad("[\(level.label)]", to: 10), level)
    }

    private func styled(_ text: String, _ level: MemoryPressureLevel) -> String {
        switch level {
        case .normal: TerminalStyle.green(text)
        case .elevated: TerminalStyle.yellow(text)
        case .critical: TerminalStyle.red(text)
        }
    }

    private var footer: [String] {
        [
            "A number in parentheses after a consumer is how many processes were grouped into that row; the bar is sized against the largest consumer listed.",
            "Per-process figures are real memory footprint (phys_footprint), which includes each process's compressed pages — the same basis Activity Monitor reports.",
            "Processes owned by another user fall back to resident size, which excludes compressed pages and therefore understates; those rows say so.",
            "\"In use\" is Maclovin's own accounting (physical minus free and speculative) and does not reproduce Activity Monitor's category math.",
            "Memory is only called reclaimable when a runtime's own CLI reports no workload — uptime alone is never treated as idleness."
        ]
    }
}
