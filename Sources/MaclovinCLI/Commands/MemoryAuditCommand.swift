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
        print(ReportPrinter.render(title: "Memory Audit", sections: sections(for: report), footer: footer))
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
            ReportRow("Pressure", report.level.label)
        ]
        if report.reclaimableBytes > 0 {
            rows.append(ReportRow("Reclaimable now", "up to \(ByteSize(report.reclaimableBytes).formatted) from runtimes reporting no workload"))
        }
        rows.append(ReportRow("Writes", "none"))
        return ReportSection(title: "Summary", rows: rows)
    }

    private func pressureSection(_ report: MemoryAuditReport) -> ReportSection {
        let rows = report.signals.map { signal in
            ReportRow(signal.name, "\(signal.measured)  [\(signal.level.label)]")
        }
        return ReportSection(title: "Pressure Signals", rows: rows)
    }

    private func runtimeSection(_ report: MemoryAuditReport) -> ReportSection {
        var rows: [ReportRow] = []
        for runtime in report.runtimes {
            rows.append(
                ReportRow(
                    runtime.name,
                    "\(runtime.size.formatted)  [\(runtime.workload.label), \(runtime.confidence.label) confidence]"
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
        let rows = report.consumers.prefix(max(0, top)).map { consumer -> ReportRow in
            var detail = consumer.size.formatted
            if consumer.processCount > 1 {
                detail += "  (\(consumer.processCount) processes)"
            }
            if consumer.basis == .resident {
                detail += "  [\(consumer.basis.label) — understates]"
            }
            return ReportRow(consumer.name, detail)
        }
        return ReportSection(title: "Largest Consumers", rows: rows)
    }

    private var footer: [String] {
        [
            "Per-process figures are real memory footprint (phys_footprint), which includes each process's compressed pages — the same basis Activity Monitor reports.",
            "Processes owned by another user fall back to resident size, which excludes compressed pages and therefore understates; those rows say so.",
            "\"In use\" is Maclovin's own accounting (physical minus free and speculative) and does not reproduce Activity Monitor's category math.",
            "Memory is only called reclaimable when a runtime's own CLI reports no workload — uptime alone is never treated as idleness."
        ]
    }
}
