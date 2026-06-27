import Foundation

// Filesystem fixtures for tests. This file imports Foundation but NOT Testing:
// the system Testing framework used here lacks the _Testing_Foundation
// cross-import overlay, so a single file cannot import both. Test files import
// only Testing + MaclovinCore and drive fixtures through these String-path helpers.
enum Fixture {
    static func tempDir() -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("maclovin-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    static func remove(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    static func makeDir(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    static func write(_ path: String, bytes: Int) {
        FileManager.default.createFile(atPath: path, contents: Data(repeating: 0x41, count: bytes))
    }

    static func symlink(_ linkPath: String, to targetPath: String) {
        try? FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: targetPath)
    }

    static func hardlink(_ newPath: String, to existingPath: String) -> Bool {
        link(existingPath, newPath) == 0
    }

    static func join(_ base: String, _ component: String) -> String {
        base + "/" + component
    }
}
