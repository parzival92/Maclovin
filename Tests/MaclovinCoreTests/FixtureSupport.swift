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

    static func url(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    static func writePlist(_ path: String, bundleID: String) {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>\(bundleID)</string>
        </dict>
        </plist>
        """
        FileManager.default.createFile(atPath: path, contents: Data(plist.utf8))
    }
}
