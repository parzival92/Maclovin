import MaclovinCore
import Testing

private let virtualizationPath =
    "/System/Library/Frameworks/Virtualization.framework/Versions/A/XPCServices/com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine"

private func makeProcess(
    pid: Int32,
    path: String,
    bytes: UInt64,
    basis: MemoryBasis = .footprint
) -> ProcessSample {
    ProcessSample(
        pid: pid,
        path: path,
        name: String(path.split(separator: "/").last ?? ""),
        bytes: bytes,
        basis: basis
    )
}

/// Builds an environment from canned command output and open-file lists.
private func makeEnvironment(
    output: [String: String] = [:],
    openPaths: [Int32: [String]] = [:]
) -> MemoryRuntimes.Environment {
    MemoryRuntimes.Environment(
        toolOutput: { tool, _ in output[tool] },
        openPaths: { openPaths[$0] ?? [] }
    )
}

private func finding(_ findings: [RuntimeFinding], named name: String) -> RuntimeFinding? {
    findings.first { $0.name.hasPrefix(name) }
}

// MARK: - Docker

@Test
func silentDockerPsMeansNoContainersNotAFailedProbe() {
    // `docker ps --quiet` prints nothing and exits 0 when nothing is running.
    // Reading that as a failed probe would hide the case worth reporting: a
    // VM holding gigabytes with no workload behind it.
    let processes = [makeProcess(pid: 1, path: "/Applications/Docker.app/Contents/MacOS/Docker Desktop", bytes: 2_000_000_000)]
    let result = MemoryRuntimes.inspect(processes: processes, environment: makeEnvironment(output: ["docker": ""]))

    let docker = finding(result.findings, named: "Docker Desktop")
    #expect(docker?.workload == .noWorkload("0 containers running"))
    #expect(docker?.workload.isReclaimable == true)
}

@Test
func runningContainersMakeDockerMemoryInUse() {
    let processes = [makeProcess(pid: 1, path: "/Applications/Docker.app/Contents/MacOS/Docker Desktop", bytes: 2_000_000_000)]
    let result = MemoryRuntimes.inspect(
        processes: processes,
        environment: makeEnvironment(output: ["docker": "abc123\ndef456"])
    )
    let docker = finding(result.findings, named: "Docker Desktop")
    #expect(docker?.workload == .active("2 containers running"))
    #expect(docker?.workload.isReclaimable == false)
    #expect(docker?.suggestion == nil)
}

@Test
func anUnreachableDockerDaemonIsUnknownNotReclaimable() {
    // A failed probe and an idle engine must not look the same: claiming
    // memory is reclaimable on no evidence is the one thing this must not do.
    let processes = [makeProcess(pid: 1, path: "/Applications/Docker.app/Contents/MacOS/Docker Desktop", bytes: 2_000_000_000)]
    let result = MemoryRuntimes.inspect(processes: processes, environment: makeEnvironment())
    let docker = finding(result.findings, named: "Docker Desktop")
    #expect(docker?.workload.isReclaimable == false)
    if case .unknown = docker?.workload {} else {
        Issue.record("expected an unknown workload, got \(String(describing: docker?.workload))")
    }
}

@Test
func dockersVirtualMachineCountsTowardDockerOnlyOnce() {
    let processes = [
        makeProcess(pid: 1, path: "/Applications/Docker.app/Contents/MacOS/Docker Desktop", bytes: 400_000_000),
        makeProcess(pid: 2, path: virtualizationPath, bytes: 1_800_000_000)
    ]
    let environment = makeEnvironment(
        output: ["docker": ""],
        openPaths: [2: ["/Users/x/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"]]
    )
    let result = MemoryRuntimes.inspect(processes: processes, environment: environment)

    #expect(result.findings.count == 1)
    #expect(result.findings[0].name == "Docker Desktop")
    #expect(result.findings[0].bytes == 2_200_000_000)
    #expect(result.processNames[2] == "Docker")
}

// MARK: - Virtual machine attribution

@Test
func aVirtualMachineIsNamedFromTheDiskImageItHoldsOpen() {
    let processes = [makeProcess(pid: 9, path: virtualizationPath, bytes: 2_384_000_000)]
    let environment = makeEnvironment(
        openPaths: [9: [
            "/System/Library/CoreServices/SystemVersion.bundle/English.lproj/SystemVersion.strings",
            "/Users/x/Library/Application Support/Claude/vm_bundles/claudevm.bundle/rootfs.img"
        ]]
    )
    let result = MemoryRuntimes.inspect(processes: processes, environment: environment)

    #expect(result.findings.count == 1)
    #expect(result.findings[0].name == "Claude (virtual machine)")
    #expect(result.findings[0].confidence == .high)
    #expect(result.processNames[9] == "Claude")
}

@Test
func systemPathsNeverIdentifyAVirtualMachinesOwner() {
    // Every process holds system bundles open; attributing a VM to macOS
    // itself would be worse than admitting the owner is unknown.
    let processes = [makeProcess(pid: 9, path: virtualizationPath, bytes: 1_000_000)]
    let environment = makeEnvironment(
        openPaths: [9: ["/System/Library/CoreServices/SystemVersion.bundle/English.lproj/SystemVersion.strings"]]
    )
    let result = MemoryRuntimes.inspect(processes: processes, environment: environment)

    #expect(result.findings[0].name == "Unidentified virtual machine")
    #expect(result.findings[0].confidence == .low)
    #expect(result.processNames.isEmpty)
}

@Test
func anAppBundleNamesAVirtualMachineAheadOfItsSupportFolder() {
    #expect(
        MemoryRuntimes.ownerFromDiskImage([
            "/Users/x/Library/Application Support/Claude/vm_bundles/claudevm.bundle/rootfs.img",
            "/Applications/Claude.app/Contents/Resources/smol-bin.arm64.img"
        ])?.owner == "Claude"
    )
}

@Test
func aVirtualMachinesWorkloadIsNeverGuessed() {
    // Maclovin cannot see inside a guest, so it must not imply the VM is idle.
    let processes = [makeProcess(pid: 9, path: virtualizationPath, bytes: 2_000_000_000)]
    let environment = makeEnvironment(openPaths: [9: ["/Applications/Claude.app/Contents/Resources/vm.img"]])
    let result = MemoryRuntimes.inspect(processes: processes, environment: environment)
    #expect(result.findings[0].workload.isReclaimable == false)
}

// MARK: - Multipass

@Test
func multipassReportsStoppedInstancesAsReclaimable() {
    let processes = [
        makeProcess(
            pid: 1,
            path: "/Library/Application Support/com.canonical.multipass/bin/qemu-system-aarch64",
            bytes: 5_000_000_000,
            basis: .resident
        )
    ]
    let listing = """
    Name          State      IPv4      Image
    cka-cp        Stopped    --        Ubuntu 24.04 LTS
    cka-w1        Stopped    --        Ubuntu 24.04 LTS
    """
    let result = MemoryRuntimes.inspect(processes: processes, environment: makeEnvironment(output: ["multipass": listing]))
    let multipass = finding(result.findings, named: "Multipass")

    #expect(multipass?.workload == .noWorkload("no instances running"))
    // Root-owned qemu is measured by resident size, which omits compressed
    // pages, so the figure is a floor and must be labelled low confidence.
    #expect(multipass?.confidence == .low)
    #expect(multipass?.evidence.contains("understates") == true)
}

@Test
func multipassNamesTheInstancesThatAreRunning() {
    let processes = [
        makeProcess(pid: 1, path: "/Library/Application Support/com.canonical.multipass/bin/qemu-system-aarch64", bytes: 5_000_000_000)
    ]
    let listing = """
    Name          State      IPv4             Image
    cka-cp        Running    192.168.252.2    Ubuntu 24.04 LTS
    cka-w1        Stopped    --               Ubuntu 24.04 LTS
    """
    let result = MemoryRuntimes.inspect(processes: processes, environment: makeEnvironment(output: ["multipass": listing]))
    let multipass = finding(result.findings, named: "Multipass")

    #expect(multipass?.workload == .active("1 instance running: cka-cp"))
    #expect(multipass?.workload.isReclaimable == false)
}

@Test
func theAlwaysOnMultipassDaemonIsNotReportedAsReclaimable() {
    // `multipassd` runs whether or not any instance does, so its memory is not
    // released by stopping instances and must not be counted as if it were.
    let processes = [
        makeProcess(pid: 1, path: "/Library/Application Support/com.canonical.multipass/bin/multipassd", bytes: 10_000_000)
    ]
    let result = MemoryRuntimes.inspect(processes: processes, environment: makeEnvironment(output: ["multipass": "Name State\n"]))
    #expect(result.findings.isEmpty)
}

@Test
func aContainerFolderAndAnAppBundleNameTheSameRuntimeIdentically() {
    // A VM found through ~/Library/Containers yields a bundle identifier,
    // while the same VM found through its .app yields the app name. Both must
    // resolve to one name or the runtime is split across two consumers.
    #expect(
        MemoryRuntimes.ownerFromDiskImage(
            ["/Users/x/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"]
        )?.owner == "Docker"
    )
    #expect(
        MemoryRuntimes.ownerFromDiskImage(
            ["/Users/x/Library/Application Support/Claude/vm_bundles/claudevm.bundle/rootfs.img"]
        )?.owner == "Claude"
    )
}
