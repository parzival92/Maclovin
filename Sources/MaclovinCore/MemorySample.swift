import Foundation

/// How a process's memory number was obtained. The two bases are not
/// comparable, so every consumer states which one produced its figure.
public enum MemoryBasis: String, Equatable, Sendable {
    /// `proc_pid_rusage`'s `ri_phys_footprint`: the process's real memory
    /// footprint, including its pages held in the compressor. This is the
    /// number Activity Monitor's "Memory" column shows.
    case footprint
    /// Resident set size from `ps`, used only when the footprint is not
    /// readable (processes owned by another user). RSS **excludes compressed
    /// pages**, so it understates — often severely, because an idle process is
    /// exactly the one macOS compresses most.
    case resident

    public var label: String {
        switch self {
        case .footprint: "real footprint"
        case .resident: "resident only"
        }
    }

    /// Confidence in the figure produced by this basis.
    public var confidence: Confidence {
        switch self {
        case .footprint: .high
        case .resident: .low
        }
    }
}

/// One sampled process.
public struct ProcessSample: Equatable, Sendable {
    public let pid: Int32
    /// Executable path, used for bundle grouping and runtime attribution.
    public let path: String
    /// Executable name (the path's last component).
    public let name: String
    public let bytes: UInt64
    public let basis: MemoryBasis

    public init(pid: Int32, path: String, name: String, bytes: UInt64, basis: MemoryBasis) {
        self.pid = pid
        self.path = path
        self.name = name
        self.bytes = bytes
        self.basis = basis
    }

    public var size: ByteSize { ByteSize(bytes) }

    /// The outermost `.app` bundle containing this executable, if any.
    ///
    /// Outermost so helper processes nested inside an app (for example
    /// `Google Chrome.app/Contents/Frameworks/…/Google Chrome Helper.app`)
    /// group under the application the user actually launched.
    public var bundleName: String? {
        for component in path.split(separator: "/") where component.hasSuffix(".app") {
            return String(component.dropLast(4))
        }
        return nil
    }
}

/// A single point-in-time reading of system memory.
///
/// Page counts are stored as sampled; byte accessors multiply by ``pageSize``.
public struct MemorySample: Equatable, Sendable {
    public let physicalBytes: UInt64
    public let pageSize: UInt64
    public let freePages: UInt64
    public let activePages: UInt64
    public let inactivePages: UInt64
    public let speculativePages: UInt64
    public let wiredPages: UInt64
    /// Pages of RAM the compressor itself occupies.
    public let compressorOccupiedPages: UInt64
    /// Uncompressed volume of everything currently held in the compressor.
    public let compressorStoredPages: UInt64
    public let swapUsedBytes: UInt64
    public let swapTotalBytes: UInt64
    public let processes: [ProcessSample]
    /// Processes whose memory could not be read at all, tallied rather than
    /// dropped silently (see ``MemoryAuditReport/permissionNote``).
    public let unreadableProcessCount: Int

    public init(
        physicalBytes: UInt64,
        pageSize: UInt64,
        freePages: UInt64,
        activePages: UInt64,
        inactivePages: UInt64,
        speculativePages: UInt64,
        wiredPages: UInt64,
        compressorOccupiedPages: UInt64,
        compressorStoredPages: UInt64,
        swapUsedBytes: UInt64,
        swapTotalBytes: UInt64,
        processes: [ProcessSample],
        unreadableProcessCount: Int
    ) {
        self.physicalBytes = physicalBytes
        self.pageSize = pageSize
        self.freePages = freePages
        self.activePages = activePages
        self.inactivePages = inactivePages
        self.speculativePages = speculativePages
        self.wiredPages = wiredPages
        self.compressorOccupiedPages = compressorOccupiedPages
        self.compressorStoredPages = compressorStoredPages
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.processes = processes
        self.unreadableProcessCount = unreadableProcessCount
    }

    private func bytes(_ pages: UInt64) -> UInt64 { pages &* pageSize }

    public var freeBytes: UInt64 { bytes(freePages) }
    public var wiredBytes: UInt64 { bytes(wiredPages) }
    public var speculativeBytes: UInt64 { bytes(speculativePages) }
    /// RAM currently occupied by the compressor.
    public var compressedBytes: UInt64 { bytes(compressorOccupiedPages) }
    /// Uncompressed volume held in the compressor — what that RAM would need
    /// if none of it were compressed.
    public var storedBytes: UInt64 { bytes(compressorStoredPages) }

    /// Memory not immediately available: everything except free and
    /// speculative pages. Maclovin's own accounting, not Activity Monitor's.
    public var usedBytes: UInt64 {
        let available = freeBytes &+ speculativeBytes
        return physicalBytes > available ? physicalBytes - available : 0
    }

    /// Memory in use as a fraction of physical memory.
    public var usedFraction: Double {
        guard physicalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(physicalBytes)
    }

    /// Free plus speculative pages, as a fraction of physical memory.
    public var headroomFraction: Double {
        guard physicalBytes > 0 else { return 0 }
        return Double(freeBytes &+ speculativeBytes) / Double(physicalBytes)
    }

    /// How much the compressor is squeezing what it holds: stored ÷ occupied.
    /// A ratio near 1 means it is barely working; a high ratio means a large
    /// working set is being kept in a small amount of RAM, which costs CPU on
    /// every access.
    public var compressionRatio: Double? {
        guard compressorOccupiedPages > 0 else { return nil }
        return Double(compressorStoredPages) / Double(compressorOccupiedPages)
    }

    /// Fraction of the swap file currently in use.
    public var swapUtilization: Double? {
        guard swapTotalBytes > 0 else { return nil }
        return Double(swapUsedBytes) / Double(swapTotalBytes)
    }
}
