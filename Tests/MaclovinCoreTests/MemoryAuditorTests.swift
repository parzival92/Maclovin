import MaclovinCore
import Testing

/// Builds a sample with 16 GB of RAM and 16 KB pages, overridable per test.
private func makeSample(
    physicalBytes: UInt64 = 16 * 1024 * 1024 * 1024,
    freePages: UInt64 = 65536,        // 1 GB
    speculativePages: UInt64 = 0,
    wiredPages: UInt64 = 131072,      // 2 GB
    compressorOccupiedPages: UInt64 = 0,
    compressorStoredPages: UInt64 = 0,
    swapUsedBytes: UInt64 = 0,
    swapTotalBytes: UInt64 = 0,
    processes: [ProcessSample] = [],
    unreadableProcessCount: Int = 0
) -> MemorySample {
    MemorySample(
        physicalBytes: physicalBytes,
        pageSize: 16384,
        freePages: freePages,
        activePages: 0,
        inactivePages: 0,
        speculativePages: speculativePages,
        wiredPages: wiredPages,
        compressorOccupiedPages: compressorOccupiedPages,
        compressorStoredPages: compressorStoredPages,
        swapUsedBytes: swapUsedBytes,
        swapTotalBytes: swapTotalBytes,
        processes: processes,
        unreadableProcessCount: unreadableProcessCount
    )
}

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

private func signal(_ sample: MemorySample, named name: String) -> MemorySignal {
    let match = MemoryAuditor.signals(for: sample).first { $0.name == name }
    #expect(match != nil, "expected a \(name) signal")
    return match ?? MemorySignal(name: name, measured: "", level: .normal, explanation: "")
}

// MARK: - Derived measurements

@Test
func compressionRatioComparesStoredVolumeToOccupiedRAM() {
    let sample = makeSample(compressorOccupiedPages: 1000, compressorStoredPages: 3500)
    #expect(sample.compressionRatio == 3.5)
    #expect(sample.compressedBytes == 1000 * 16384)
    #expect(sample.storedBytes == 3500 * 16384)
}

@Test
func compressionRatioIsAbsentWhenCompressorIsUnused() {
    #expect(makeSample().compressionRatio == nil)
}

@Test
func usedBytesExcludeFreeAndSpeculativePages() {
    // 16 GB physical, 1 GB free + 1 GB speculative => 14 GB in use.
    let sample = makeSample(freePages: 65536, speculativePages: 65536)
    #expect(sample.usedBytes == 14 * 1024 * 1024 * 1024)
    #expect(sample.headroomFraction == 0.125)
}

// MARK: - Swap signal

@Test
func unusedSwapIsNormal() {
    #expect(signal(makeSample(), named: "Swap").level == .normal)
}

@Test
func partiallyUsedSwapIsElevated() {
    let sample = makeSample(swapUsedBytes: 1_000_000_000, swapTotalBytes: 8_000_000_000)
    #expect(signal(sample, named: "Swap").level == .elevated)
}

@Test
func nearlyFullSwapIsCritical() {
    // The state that prompted this command: 6.79 GB used of an 8 GB swap file.
    let sample = makeSample(swapUsedBytes: 6_787_235_840, swapTotalBytes: 8_589_934_592)
    let swap = signal(sample, named: "Swap")
    #expect(swap.level == .critical)
    #expect(swap.measured.contains("79%"))
}

// MARK: - Compressor signal

@Test
func hardWorkingCompressorIsCritical() {
    // 6.0 GB of RAM holding 21 GB uncompressed: a 3.5x ratio.
    let sample = makeSample(compressorOccupiedPages: 393216, compressorStoredPages: 1376256)
    #expect(signal(sample, named: "Compressor").level == .critical)
}

@Test
func smallCompressorIsNormalHoweverWellItCompresses() {
    // A 10x ratio over just 16 MB of RAM is not worth flagging.
    let sample = makeSample(compressorOccupiedPages: 1000, compressorStoredPages: 10000)
    #expect(signal(sample, named: "Compressor").level == .normal)
}

// MARK: - Headroom signal

@Test
func lowHeadroomIsElevatedButNeverCriticalOnItsOwn() {
    // macOS keeps free memory low by design, so scarce free memory alone must
    // not raise a critical verdict.
    let sample = makeSample(freePages: 512)
    let headroom = signal(sample, named: "Headroom")
    #expect(headroom.level == .elevated)
    #expect(MemoryAuditor.signals(for: sample).allSatisfy { $0.level < .critical })
}

@Test
func overallLevelIsTheWorstSignal() {
    let sample = makeSample(swapUsedBytes: 7_800_000_000, swapTotalBytes: 8_000_000_000)
    let report = MemoryAuditReport(sample: sample, signals: MemoryAuditor.signals(for: sample), consumers: [], runtimes: [])
    #expect(report.level == .critical)
}

// MARK: - Consumer grouping

@Test
func helperProcessesGroupUnderTheOutermostAppBundle() {
    let processes = [
        makeProcess(pid: 1, path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", bytes: 100),
        makeProcess(
            pid: 2,
            path: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper",
            bytes: 200
        )
    ]
    let consumers = MemoryAuditor.consumers(in: processes)
    #expect(consumers.count == 1)
    #expect(consumers[0].name == "Google Chrome")
    #expect(consumers[0].bytes == 300)
    #expect(consumers[0].processCount == 2)
}

@Test
func processesSharingAnExecutableAreNeverGroupedTogether() {
    // Two Apple Virtualization VM hosts share one executable but are entirely
    // unrelated machines; merging them would invent a consumer that does not exist.
    let path = "/System/Library/Frameworks/Virtualization.framework/XPCServices/com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine"
    let consumers = MemoryAuditor.consumers(in: [
        makeProcess(pid: 1, path: path, bytes: 100),
        makeProcess(pid: 2, path: path, bytes: 200)
    ])
    #expect(consumers.count == 2)
    #expect(consumers.map(\.bytes) == [200, 100])
}

@Test
func anAttributedVirtualMachineGroupsUnderTheAppThatOwnsIt() {
    let processes = [
        makeProcess(pid: 1, path: "/Applications/Docker.app/Contents/MacOS/Docker Desktop", bytes: 100),
        makeProcess(pid: 2, path: "/System/Library/Frameworks/Virtualization.framework/com.apple.Virtualization.VirtualMachine", bytes: 900)
    ]
    let consumers = MemoryAuditor.consumers(in: processes, names: [2: "Docker"])
    #expect(consumers.count == 1)
    #expect(consumers[0].name == "Docker")
    #expect(consumers[0].bytes == 1000)
}

@Test
func oneResidentOnlyMemberMakesTheWholeGroupALowerBound() {
    let processes = [
        makeProcess(pid: 1, path: "/Applications/Claude.app/Contents/MacOS/Claude", bytes: 100),
        makeProcess(pid: 2, path: "/Applications/Claude.app/Contents/MacOS/Helper", bytes: 200, basis: .resident)
    ]
    let consumers = MemoryAuditor.consumers(in: processes)
    #expect(consumers[0].basis == .resident)
    #expect(consumers[0].basis.confidence == .low)
}

// MARK: - Permission reporting

@Test
func measurementGapsAreReportedRatherThanHidden() {
    let processes = [makeProcess(pid: 1, path: "/usr/sbin/root-owned", bytes: 100, basis: .resident)]
    let report = MemoryAuditReport(
        sample: makeSample(processes: processes, unreadableProcessCount: 3),
        signals: [],
        consumers: MemoryAuditor.consumers(in: processes),
        runtimes: []
    )
    let note = report.permissionNote
    #expect(note?.contains("understates") == true)
    #expect(note?.contains("3 not readable") == true)
}

@Test
func aFullyMeasuredSampleReportsNoGap() {
    let report = MemoryAuditReport(sample: makeSample(), signals: [], consumers: [], runtimes: [])
    #expect(report.permissionNote == nil)
}
