import Foundation

/// Whether a runtime is doing work that justifies the memory it holds.
///
/// This is deliberately not "idle time". A long uptime proves nothing — a VM
/// that has been up for nine days may be serving a cluster. Maclovin only
/// claims memory is reclaimable when the runtime's own CLI reports that it has
/// nothing to run.
public enum RuntimeWorkload: Equatable, Sendable {
    /// The runtime reports active work; its memory is in use.
    case active(String)
    /// The runtime reports no work at all, so its memory is reclaimable.
    case noWorkload(String)
    /// The runtime's state could not be determined.
    case unknown(String)

    public var detail: String {
        switch self {
        case .active(let detail), .noWorkload(let detail), .unknown(let detail):
            detail
        }
    }

    public var label: String {
        switch self {
        case .active: "In use"
        case .noWorkload: "Reclaimable"
        case .unknown: "Unknown"
        }
    }

    public var isReclaimable: Bool {
        if case .noWorkload = self { return true }
        return false
    }
}

/// A virtualization or container runtime holding memory, with the evidence for
/// what it is and whether it is being used.
public struct RuntimeFinding: Equatable, Sendable {
    public let name: String
    public let bytes: UInt64
    public let processCount: Int
    public let workload: RuntimeWorkload
    /// Confidence that this memory belongs to the named runtime.
    public let confidence: Confidence
    /// What identified it — an executable path, or a VM disk image it holds open.
    public let evidence: String
    /// The command that would release the memory, when one is safe to name.
    /// Read-only audit never runs it.
    public let suggestion: String?

    public init(
        name: String,
        bytes: UInt64,
        processCount: Int,
        workload: RuntimeWorkload,
        confidence: Confidence,
        evidence: String,
        suggestion: String? = nil
    ) {
        self.name = name
        self.bytes = bytes
        self.processCount = processCount
        self.workload = workload
        self.confidence = confidence
        self.evidence = evidence
        self.suggestion = suggestion
    }

    public var size: ByteSize { ByteSize(bytes) }
}

/// Runtime findings plus the process renames they establish.
public struct RuntimeInspection: Equatable, Sendable {
    public let findings: [RuntimeFinding]
    /// Display name by pid, for processes whose executable path does not
    /// identify them — currently Apple Virtualization VM hosts.
    public let processNames: [Int32: String]

    public init(findings: [RuntimeFinding], processNames: [Int32: String]) {
        self.findings = findings
        self.processNames = processNames
    }
}

/// Identifies virtualization runtimes and asks each one whether it is busy.
///
/// Virtual machines are the reason a Mac can look inexplicably full: a VM
/// holds its whole configured memory whether or not the guest is doing
/// anything, and the host process is often named after the virtualization
/// framework rather than the app that started it. This inspector names the VM
/// from the disk image it holds open, then asks the runtime's own CLI whether
/// there is any workload behind it.
public enum MemoryRuntimes {
    /// Injectable probes. Defaults run the real read-only commands.
    public struct Environment: Sendable {
        /// Runs a read-only probe, returning trimmed stdout or nil on failure.
        public var toolOutput: @Sendable (_ tool: String, _ arguments: [String]) -> String?
        /// Returns the file paths a process holds open, for VM attribution.
        public var openPaths: @Sendable (_ pid: Int32) -> [String]

        public init(
            toolOutput: @escaping @Sendable (_ tool: String, _ arguments: [String]) -> String? = {
                MemoryRuntimes.probe($0, $1)
            },
            openPaths: @escaping @Sendable (_ pid: Int32) -> [String] = { MemoryRuntimes.openPaths(of: $0) }
        ) {
            self.toolOutput = toolOutput
            self.openPaths = openPaths
        }
    }

    /// Path fragment identifying each supported runtime's own processes.
    static let multipassMarker = "com.canonical.multipass"
    static let appleVirtualizationMarker = "com.apple.Virtualization.VirtualMachine"

    public static func inspect(
        processes: [ProcessSample],
        environment: Environment = Environment()
    ) -> RuntimeInspection {
        var findings: [RuntimeFinding] = []
        // Apple Virtualization VM hosts are attributed to an owning app, so
        // they are claimed by name and must not be double-counted elsewhere.
        var owners = attributeVirtualMachines(processes: processes, environment: environment)

        // Every VM traced to an owner is renamed to that owner, so its memory
        // is listed under the app the user recognises rather than under the
        // virtualization framework's executable, which names every VM
        // identically and none of them usefully.
        let names = owners.reduce(into: [Int32: String]()) { result, entry in
            if let owner = entry.owner { result[entry.process.pid] = owner }
        }

        if let multipass = multipassFinding(processes: processes, environment: environment) {
            findings.append(multipass)
        }
        if let docker = dockerFinding(processes: processes, vmOwners: &owners, environment: environment) {
            findings.append(docker)
        }
        findings.append(contentsOf: remainingVirtualMachines(owners))

        return RuntimeInspection(
            findings: findings.sorted { $0.bytes > $1.bytes },
            processNames: names
        )
    }

    /// Pluralizes a count for report text: "1 process", "3 processes".
    static func pluralized(_ count: Int, _ noun: String) -> String {
        guard count != 1 else { return "1 \(noun)" }
        let suffix = ["s", "x", "ch", "sh"].contains(where: noun.hasSuffix) ? "es" : "s"
        return "\(count) \(noun)\(suffix)"
    }

    // MARK: - Apple Virtualization attribution

    /// One `com.apple.Virtualization.VirtualMachine` process and the app it
    /// was traced back to.
    struct VirtualMachineOwner: Equatable {
        let process: ProcessSample
        /// Owning app name, when a disk image identified one.
        let owner: String?
        let evidence: String
    }

    /// Names each Apple Virtualization VM from the disk image it holds open.
    ///
    /// These processes are XPC services reparented to `launchd`, so the parent
    /// pid says nothing about which app started them and every one of them has
    /// the same executable path. The VM's backing image is the only direct
    /// evidence available without privileges.
    static func attributeVirtualMachines(
        processes: [ProcessSample],
        environment: Environment
    ) -> [VirtualMachineOwner] {
        processes
            .filter { $0.path.contains(appleVirtualizationMarker) }
            .map { process in
                let paths = environment.openPaths(process.pid)
                if let (owner, path) = ownerFromDiskImage(paths) {
                    return VirtualMachineOwner(process: process, owner: owner, evidence: path)
                }
                return VirtualMachineOwner(
                    process: process,
                    owner: nil,
                    evidence: "pid \(process.pid), owning app not identified"
                )
            }
    }

    /// File extensions that indicate a VM's backing storage or boot media.
    static let diskImageExtensions = ["img", "raw", "qcow2", "vmdk", "iso", "bundle"]

    /// Derives an owning app from the paths a VM process holds open.
    ///
    /// System paths are ignored: every process opens things under `/System`,
    /// and those identify macOS rather than the VM's owner.
    public static func ownerFromDiskImage(_ paths: [String]) -> (owner: String, path: String)? {
        let candidates = paths.filter { path in
            guard !path.hasPrefix("/System/"), !path.hasPrefix("/usr/") else { return false }
            return diskImageExtensions.contains { path.hasSuffix(".\($0)") }
        }

        // An `.app` component names the app directly; otherwise the folder the
        // app owns under Application Support or Containers does.
        for path in candidates {
            let components = path.split(separator: "/").map(String.init)
            if let app = components.first(where: { $0.hasSuffix(".app") }) {
                return (String(app.dropLast(4)), path)
            }
        }
        for path in candidates {
            let components = path.split(separator: "/").map(String.init)
            for marker in ["Application Support", "Containers", "Group Containers"] {
                if let index = components.firstIndex(of: marker), index + 1 < components.count {
                    return (displayName(forOwner: components[index + 1]), path)
                }
            }
        }
        return nil
    }

    /// Turns a container folder name into the app name a user would recognise.
    ///
    /// Container folders are named by bundle identifier, so a VM found only
    /// through `~/Library/Containers` yields `com.docker.docker` where the
    /// same VM found through its `.app` yields `Docker`. Both must produce one
    /// name, or the runtime's own processes and its VM are reported as two
    /// unrelated consumers.
    static func displayName(forOwner owner: String) -> String {
        let components = owner.split(separator: ".").map(String.init)
        guard components.count >= 3,
              ["com", "io", "org", "net", "dev", "app", "group"].contains(components[0]),
              let last = components.last,
              !last.isEmpty
        else { return owner }
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    /// VM hosts not claimed by a named runtime, reported on their own.
    static func remainingVirtualMachines(_ owners: [VirtualMachineOwner]) -> [RuntimeFinding] {
        owners.map { entry in
            RuntimeFinding(
                name: entry.owner.map { "\($0) (virtual machine)" } ?? "Unidentified virtual machine",
                bytes: entry.process.bytes,
                processCount: 1,
                workload: .unknown("Maclovin cannot see inside a VM to tell whether the guest is busy"),
                confidence: entry.owner == nil ? .low : .high,
                evidence: entry.owner == nil ? entry.evidence : "holds open \(entry.evidence)",
                suggestion: entry.owner.map { "Quit \($0) if you are not using it." }
            )
        }
    }

    // MARK: - Multipass

    static func multipassFinding(
        processes: [ProcessSample],
        environment: Environment
    ) -> RuntimeFinding? {
        // Only the qemu hosts hold instance memory. `multipassd` runs whether
        // or not any instance does, so its few megabytes are not reclaimable
        // by stopping instances and must not be reported as if they were.
        let owned = processes.filter { $0.path.contains(multipassMarker) && $0.name.contains("qemu") }
        guard !owned.isEmpty else { return nil }

        let bytes = owned.reduce(UInt64(0)) { $0 + $1.bytes }
        let understated = owned.contains { $0.basis == .resident }
        let workload: RuntimeWorkload

        if let listing = environment.toolOutput("multipass", ["list"]) {
            let running = instanceNames(in: listing, state: "Running")
            workload = running.isEmpty
                ? .noWorkload("no instances running")
                : .active("\(running.count) instance\(running.count == 1 ? "" : "s") running: \(running.joined(separator: ", "))")
        } else {
            workload = .unknown("`multipass list` did not answer")
        }

        return RuntimeFinding(
            name: "Multipass",
            bytes: bytes,
            processCount: owned.count,
            workload: workload,
            // The qemu hosts run as root, so their footprint is usually only
            // readable as resident size, which omits compressed pages.
            confidence: understated ? .low : .high,
            evidence: understated
                ? "\(pluralized(owned.count, "qemu host")); root-owned, so this is resident size and understates the real footprint"
                : "\(pluralized(owned.count, "qemu host")) under \(multipassMarker)",
            suggestion: workload.isReclaimable ? nil : "`multipass stop <instance>` releases an instance's memory."
        )
    }

    /// Instance names in a `multipass list` table that are in the given state.
    static func instanceNames(in listing: String, state: String) -> [String] {
        listing
            .split(separator: "\n")
            .dropFirst()  // header row
            .compactMap { line in
                let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                guard fields.count >= 2, fields[1] == state else { return nil }
                return String(fields[0])
            }
    }

    // MARK: - Docker

    static func dockerFinding(
        processes: [ProcessSample],
        vmOwners: inout [VirtualMachineOwner],
        environment: Environment
    ) -> RuntimeFinding? {
        var owned = processes.filter { process in
            process.bundleName == "Docker" || process.name.hasPrefix("com.docker.")
        }

        // Docker Desktop's guest runs in an Apple Virtualization VM whose
        // executable path is the shared framework, so it only joins the Docker
        // total once its disk image has identified it.
        let dockerVMs = vmOwners.filter { $0.owner == "Docker" }
        vmOwners.removeAll { $0.owner == "Docker" }
        owned.append(contentsOf: dockerVMs.map(\.process))

        guard !owned.isEmpty else { return nil }

        let bytes = owned.reduce(UInt64(0)) { $0 + $1.bytes }
        let workload: RuntimeWorkload
        if let output = environment.toolOutput("docker", ["ps", "--quiet"]) {
            let containers = output.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            workload = containers.isEmpty
                ? .noWorkload("0 containers running")
                : .active("\(containers.count) container\(containers.count == 1 ? "" : "s") running")
        } else {
            // A silent `docker ps` means the daemon is unreachable, which does
            // not prove there is no workload — an unstarted engine and a
            // failed probe look the same from here.
            workload = .unknown("`docker ps` did not answer")
        }

        let vmNote = dockerVMs.isEmpty ? "" : ", including its Linux VM"
        return RuntimeFinding(
            name: "Docker Desktop",
            bytes: bytes,
            processCount: owned.count,
            workload: workload,
            confidence: .high,
            evidence: "\(pluralized(owned.count, "process"))\(vmNote)",
            suggestion: workload.isReclaimable ? "Quit Docker Desktop; it restarts in seconds when you need it." : nil
        )
    }
}

// MARK: - Open-file probe

extension MemoryRuntimes {
    /// Runs a read-only probe, returning stdout on success and nil on failure.
    ///
    /// Unlike ``Shell/output(_:_:timeout:)`` this preserves empty output as a
    /// successful answer. The distinction decides a verdict here: `docker ps
    /// --quiet` prints nothing and exits 0 when no containers are running, and
    /// treating that as a failed probe would hide the very case worth
    /// reporting — a VM holding gigabytes with no workload behind it.
    public static func probe(_ tool: String, _ arguments: [String]) -> String? {
        guard let result = try? Shell.run(tool, arguments, timeout: 15), result.succeeded else {
            return nil
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Paths a process holds open, via `lsof -Fn` (read-only).
    ///
    /// Used only for the handful of virtualization processes found, so the
    /// cost stays bounded. Returns an empty list when `lsof` is unavailable or
    /// declines to describe the process.
    public static func openPaths(of pid: Int32) -> [String] {
        guard let output = Shell.output("lsof", ["-p", "\(pid)", "-Fn"], timeout: 10) else { return [] }
        return output
            .split(separator: "\n")
            .filter { $0.hasPrefix("n/") }
            .map { String($0.dropFirst()) }
    }
}
