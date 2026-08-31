import Foundation

/// How hard the system is working to fit its workload into physical memory.
public enum MemoryPressureLevel: Int, Comparable, CaseIterable, Sendable {
    case normal
    case elevated
    case critical

    public static func < (lhs: MemoryPressureLevel, rhs: MemoryPressureLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .normal: "Normal"
        case .elevated: "Elevated"
        case .critical: "Critical"
        }
    }
}

/// One measured indicator, its threshold verdict, and what it means.
///
/// Signals are reported individually rather than collapsed into a single
/// score, because they fail in different ways and call for different fixes.
public struct MemorySignal: Equatable, Sendable {
    public let name: String
    /// The measurement itself, so the verdict can be checked against it.
    public let measured: String
    public let level: MemoryPressureLevel
    public let explanation: String

    public init(name: String, measured: String, level: MemoryPressureLevel, explanation: String) {
        self.name = name
        self.measured = measured
        self.level = level
        self.explanation = explanation
    }
}

/// An application or process holding memory.
public struct MemoryConsumer: Equatable, Sendable {
    public let name: String
    public let bytes: UInt64
    public let processCount: Int
    /// Weakest basis among the grouped processes: one resident-only member
    /// makes the whole total a lower bound.
    public let basis: MemoryBasis

    public init(name: String, bytes: UInt64, processCount: Int, basis: MemoryBasis) {
        self.name = name
        self.bytes = bytes
        self.processCount = processCount
        self.basis = basis
    }

    public var size: ByteSize { ByteSize(bytes) }
}

/// The full memory audit.
public struct MemoryAuditReport: Equatable, Sendable {
    public let sample: MemorySample
    public let signals: [MemorySignal]
    /// Consumers sorted largest first.
    public let consumers: [MemoryConsumer]
    /// Virtualization runtimes, sorted largest first.
    public let runtimes: [RuntimeFinding]

    public init(
        sample: MemorySample,
        signals: [MemorySignal],
        consumers: [MemoryConsumer],
        runtimes: [RuntimeFinding]
    ) {
        self.sample = sample
        self.signals = signals
        self.consumers = consumers
        self.runtimes = runtimes
    }

    /// The overall level: the worst of the individual signals.
    public var level: MemoryPressureLevel {
        signals.map(\.level).max() ?? .normal
    }

    /// Memory held by runtimes that report no workload at all.
    public var reclaimableBytes: UInt64 {
        runtimes.filter { $0.workload.isReclaimable }.reduce(0) { $0 + $1.bytes }
    }

    /// Stated when some processes could not be measured at full fidelity.
    public var permissionNote: String? {
        let understated = consumers.filter { $0.basis == .resident }.count
        let unreadable = sample.unreadableProcessCount
        guard understated > 0 || unreadable > 0 else { return nil }

        var parts: [String] = []
        if understated > 0 {
            parts.append("\(understated) owned by another user, measured as resident size only (understates: excludes compressed pages)")
        }
        if unreadable > 0 {
            parts.append("\(unreadable) not readable at all")
        }
        return parts.joined(separator: "; ")
    }
}

/// Explains where physical memory went, and which of it is reclaimable.
///
/// The audit is read-only and never signals, stops, or kills a process.
///
/// It deliberately leads with swap and compressor state rather than "memory
/// used". macOS fills unused RAM by design, so a high used figure is normal;
/// what actually costs the user time is the compressor working hard and pages
/// travelling to swap.
public enum MemoryAuditor {
    /// Swap use above this fraction of the swap file is treated as critical.
    static let criticalSwapUtilization = 0.75
    /// Compressor ratios at or above these values are elevated and critical.
    static let elevatedCompressionRatio = 2.0
    static let criticalCompressionRatio = 3.5
    /// A compressor smaller than this fraction of RAM is not worth flagging
    /// however well it is compressing.
    static let compressorSignificanceFraction = 0.05
    /// Free plus speculative memory below this fraction of RAM is elevated.
    static let lowHeadroomFraction = 0.02

    public static func audit(
        sample: MemorySample,
        runtimeEnvironment: MemoryRuntimes.Environment = MemoryRuntimes.Environment()
    ) -> MemoryAuditReport {
        let inspection = MemoryRuntimes.inspect(processes: sample.processes, environment: runtimeEnvironment)
        return MemoryAuditReport(
            sample: sample,
            signals: signals(for: sample),
            consumers: consumers(in: sample.processes, names: inspection.processNames),
            runtimes: inspection.findings
        )
    }

    // MARK: - Signals

    public static func signals(for sample: MemorySample) -> [MemorySignal] {
        [swapSignal(sample), compressorSignal(sample), headroomSignal(sample)]
    }

    static func swapSignal(_ sample: MemorySample) -> MemorySignal {
        let used = ByteSize(sample.swapUsedBytes).formatted
        let total = ByteSize(sample.swapTotalBytes).formatted

        guard sample.swapUsedBytes > 0 else {
            return MemorySignal(
                name: "Swap",
                measured: "none in use",
                level: .normal,
                explanation: "Nothing has been pushed out to disk."
            )
        }

        let utilization = sample.swapUtilization ?? 0
        let measured = sample.swapTotalBytes > 0
            ? "\(used) of \(total) (\(percent(utilization)))"
            : used

        if utilization >= criticalSwapUtilization {
            return MemorySignal(
                name: "Swap",
                measured: measured,
                level: .critical,
                explanation: "The swap file is nearly full. macOS grows it on demand, but pages are moving to disk continuously and every miss costs real time."
            )
        }
        return MemorySignal(
            name: "Swap",
            measured: measured,
            level: .elevated,
            explanation: "Some memory has been written to disk. Occasional swap is normal; a large, persistent amount means the workload does not fit in RAM."
        )
    }

    static func compressorSignal(_ sample: MemorySample) -> MemorySignal {
        guard let ratio = sample.compressionRatio, sample.compressedBytes > 0 else {
            return MemorySignal(
                name: "Compressor",
                measured: "not in use",
                level: .normal,
                explanation: "Nothing is being held compressed."
            )
        }

        let measured = "\(ByteSize(sample.storedBytes).formatted) held in \(ByteSize(sample.compressedBytes).formatted) (\(ratioText(ratio)))"
        let significant = Double(sample.compressedBytes) >= Double(sample.physicalBytes) * compressorSignificanceFraction

        guard significant else {
            return MemorySignal(
                name: "Compressor",
                measured: measured,
                level: .normal,
                explanation: "The compressor holds too little to matter."
            )
        }
        if ratio >= criticalCompressionRatio {
            return MemorySignal(
                name: "Compressor",
                measured: measured,
                level: .critical,
                explanation: "A working set far larger than the RAM backing it is being kept compressed. Every access to those pages costs CPU to decompress."
            )
        }
        if ratio >= elevatedCompressionRatio {
            return MemorySignal(
                name: "Compressor",
                measured: measured,
                level: .elevated,
                explanation: "The compressor is doing steady work to keep the workload resident."
            )
        }
        return MemorySignal(
            name: "Compressor",
            measured: measured,
            level: .normal,
            explanation: "The compressor is holding data without straining."
        )
    }

    static func headroomSignal(_ sample: MemorySample) -> MemorySignal {
        let fraction = sample.headroomFraction
        let measured = "\(ByteSize(sample.freeBytes &+ sample.speculativeBytes).formatted) free of \(ByteSize(sample.physicalBytes).formatted) (\(percent(fraction)))"

        // Never critical on its own. macOS deliberately leaves little memory
        // idle, so low free memory is only meaningful alongside swap and
        // compressor pressure, which have their own signals.
        if fraction < lowHeadroomFraction {
            return MemorySignal(
                name: "Headroom",
                measured: measured,
                level: .elevated,
                explanation: "Almost no memory is immediately available, so a new allocation must first reclaim from something else."
            )
        }
        return MemorySignal(
            name: "Headroom",
            measured: measured,
            level: .normal,
            explanation: "Memory is available without reclaiming. macOS keeps free memory low by design; this is not wasted space."
        )
    }

    // MARK: - Consumers

    /// Groups processes into what the user recognises: an app, or a single
    /// standalone process.
    ///
    /// Grouping is only ever by owning `.app` bundle, which is direct evidence
    /// from the executable path. Processes are never grouped by name — two
    /// processes sharing an executable can be entirely unrelated, which is
    /// exactly the case for virtual machine hosts.
    /// - Parameter names: Display names by pid, from ``MemoryRuntimes``. A VM
    ///   host attributed to an app groups under that app, so the app's row
    ///   accounts for the memory it is really responsible for.
    public static func consumers(
        in processes: [ProcessSample],
        names: [Int32: String] = [:]
    ) -> [MemoryConsumer] {
        var grouped: [String: (bytes: UInt64, count: Int, basis: MemoryBasis)] = [:]
        var standalone: [MemoryConsumer] = []

        for process in processes {
            guard let key = names[process.pid] ?? process.bundleName else {
                standalone.append(
                    MemoryConsumer(name: process.name, bytes: process.bytes, processCount: 1, basis: process.basis)
                )
                continue
            }
            var entry = grouped[key] ?? (0, 0, .footprint)
            entry.bytes &+= process.bytes
            entry.count += 1
            if process.basis == .resident { entry.basis = .resident }
            grouped[key] = entry
        }

        let bundles = grouped.map { name, entry in
            MemoryConsumer(name: name, bytes: entry.bytes, processCount: entry.count, basis: entry.basis)
        }
        return (bundles + standalone).sorted { $0.bytes > $1.bytes }
    }

    // MARK: - Formatting helpers

    public static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }

    static func ratioText(_ ratio: Double) -> String {
        String(format: "%.1fx", ratio)
    }
}
