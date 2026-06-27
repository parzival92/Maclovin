import Foundation

public enum MaclovinPaths {
    public static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    public static var configFile: URL {
        homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("maclovin", isDirectory: true)
            .appendingPathComponent("config.toml")
    }

    public static var historyDirectory: URL {
        homeDirectory
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("maclovin", isDirectory: true)
    }

    public static func expandTilde(in path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else {
            return path
        }

        return homeDirectory.path + String(path.dropFirst())
    }
}
