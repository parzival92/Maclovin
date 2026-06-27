import MaclovinCore
import Testing

@Test
func measuresFilesAcrossSubdirectories() {
    let root = Fixture.tempDir()
    defer { Fixture.remove(root) }

    Fixture.write(Fixture.join(root, "a.bin"), bytes: 10_000)
    Fixture.write(Fixture.join(root, "b.bin"), bytes: 10_000)
    let sub = Fixture.join(root, "nested")
    Fixture.makeDir(sub)
    Fixture.write(Fixture.join(sub, "c.bin"), bytes: 10_000)

    let result = DirectorySizer.measure(atPath: root)

    #expect(result.fileCount == 3)
    #expect(result.unreadableCount == 0)
    #expect(result.bytes >= 30_000)
}

@Test
func doesNotFollowSymlinks() {
    let root = Fixture.tempDir()
    defer { Fixture.remove(root) }

    let target = Fixture.join(root, "real.bin")
    Fixture.write(target, bytes: 50_000)
    Fixture.symlink(Fixture.join(root, "link.bin"), to: target)

    let result = DirectorySizer.measure(atPath: root)

    // Only the real file is counted; the symlink adds no bytes and no count.
    #expect(result.fileCount == 1)
}

@Test
func countsHardlinkedFileOnce() {
    let root = Fixture.tempDir()
    defer { Fixture.remove(root) }

    let original = Fixture.join(root, "orig.bin")
    Fixture.write(original, bytes: 64_000)
    #expect(Fixture.hardlink(Fixture.join(root, "hard.bin"), to: original))

    let result = DirectorySizer.measure(atPath: root)

    // Two directory entries, one inode: counted once.
    #expect(result.fileCount == 1)
}
