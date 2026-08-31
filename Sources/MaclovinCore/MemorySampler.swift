import Darwin
import Foundation

/// Reads live system memory state.
///
/// Everything here is read-only: three kernel interfaces and, only for the
/// processes the kernel refuses to describe, one `ps` fallback.
///
/// - `host_statistics64(HOST_VM_INFO64)` for page counts and compressor state.
/// - `sysctlbyname("vm.swapusage")` for swap.
/// - `proc_pid_rusage(RUSAGE_INFO_V4)` for each process's `ri_phys_footprint`.
///
/// `phys_footprint` is the metric Activity Monitor reports, and it is the only
/// per-process number worth ranking by: resident size omits pages held in the
/// compressor, so an idle memory hog can report a small RSS while actually
/// holding gigabytes.
public enum MemorySampler {
    /// Samples the live system. Returns nil only if the kernel VM statistics
    /// call fails, which would leave nothing meaningful to report.
    public static func sample(
        toolOutput: (_ tool: String, _ arguments: [String]) -> String? = { Shell.output($0, $1, timeout: 15) }
    ) -> MemorySample? {
        guard let vm = virtualMemoryStatistics() else { return nil }

        let swap = swapUsage()
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let resolvedPageSize = UInt64(pageSize == 0 ? 4096 : pageSize)

        let (processes, unreadable) = sampleProcesses(toolOutput: toolOutput)

        return MemorySample(
            physicalBytes: ProcessInfo.processInfo.physicalMemory,
            pageSize: resolvedPageSize,
            freePages: UInt64(vm.free_count),
            activePages: UInt64(vm.active_count),
            inactivePages: UInt64(vm.inactive_count),
            speculativePages: UInt64(vm.speculative_count),
            wiredPages: UInt64(vm.wire_count),
            compressorOccupiedPages: UInt64(vm.compressor_page_count),
            compressorStoredPages: vm.total_uncompressed_pages_in_compressor,
            swapUsedBytes: swap?.used ?? 0,
            swapTotalBytes: swap?.total ?? 0,
            processes: processes,
            unreadableProcessCount: unreadable
        )
    }

    // MARK: - Kernel readings

    static func virtualMemoryStatistics() -> vm_statistics64_data_t? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? stats : nil
    }

    static func swapUsage() -> (used: UInt64, total: UInt64)? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return (UInt64(usage.xsu_used), UInt64(usage.xsu_total))
    }

    // MARK: - Per-process sampling

    /// Samples every process, preferring `phys_footprint` and falling back to
    /// `ps` resident size for processes owned by another user.
    static func sampleProcesses(
        toolOutput: (_ tool: String, _ arguments: [String]) -> String?
    ) -> (samples: [ProcessSample], unreadable: Int) {
        let pids = listProcessIDs()
        var samples: [ProcessSample] = []
        var needsFallback: [Int32] = []

        for pid in pids where pid > 0 {
            guard let path = executablePath(pid) else {
                // No path means no way to name or group it; the resident
                // fallback below still needs a name, so treat it as unreadable.
                needsFallback.append(pid)
                continue
            }
            if let bytes = physicalFootprint(pid) {
                samples.append(
                    ProcessSample(
                        pid: pid,
                        path: path,
                        name: (path as NSString).lastPathComponent,
                        bytes: bytes,
                        basis: .footprint
                    )
                )
            } else {
                needsFallback.append(pid)
            }
        }

        guard !needsFallback.isEmpty else { return (samples, 0) }

        let resident = residentSizes(toolOutput: toolOutput)
        var unreadable = 0
        for pid in needsFallback {
            guard let entry = resident[pid] else {
                unreadable += 1
                continue
            }
            samples.append(
                ProcessSample(
                    pid: pid,
                    path: entry.path,
                    name: (entry.path as NSString).lastPathComponent,
                    bytes: entry.bytes,
                    basis: .resident
                )
            )
        }
        return (samples, unreadable)
    }

    static func listProcessIDs() -> [Int32] {
        var capacity = 4096
        for _ in 0..<4 {
            var pids = [pid_t](repeating: 0, count: capacity)
            let byteCount = proc_listpids(
                UInt32(PROC_ALL_PIDS), 0, &pids, Int32(capacity * MemoryLayout<pid_t>.size)
            )
            guard byteCount > 0 else { return [] }
            let returned = Int(byteCount) / MemoryLayout<pid_t>.size
            // A full buffer may mean the list was truncated; retry larger.
            if returned < capacity { return Array(pids.prefix(returned)) }
            capacity *= 2
        }
        return []
    }

    static func physicalFootprint(_ pid: Int32) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }

    /// `PROC_PIDPATHINFO_MAXSIZE` from `<sys/proc_info.h>`; it is a macro, so
    /// it is not visible to Swift.
    static let executablePathMaxLength = 4 * Int(MAXPATHLEN)

    static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: executablePathMaxLength)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        let path = String(decoding: bytes, as: UTF8.self)
        return path.isEmpty ? nil : path
    }

    /// Resident sizes from `ps`, for processes `proc_pid_rusage` refused.
    /// Keyed by pid; sizes are KiB in `ps` output.
    static func residentSizes(
        toolOutput: (_ tool: String, _ arguments: [String]) -> String?
    ) -> [Int32: (bytes: UInt64, path: String)] {
        guard let output = toolOutput("/bin/ps", ["-Axo", "pid=,rss=,comm="]) else { return [:] }

        var result: [Int32: (bytes: UInt64, path: String)] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3,
                  let pid = Int32(fields[0]),
                  let kilobytes = UInt64(fields[1])
            else { continue }
            result[pid] = (kilobytes &* 1024, String(fields[2]))
        }
        return result
    }
}
