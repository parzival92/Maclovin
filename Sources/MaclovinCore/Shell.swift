import Foundation

/// The captured result of running an external tool.
public struct ShellResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { exitCode == 0 }

    /// stdout split into non-empty trimmed lines.
    public var stdoutLines: [String] {
        stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Runs trusted local tools (`brew`, `xcrun`, …) with captured output.
///
/// Maclovin only ever invokes a fixed set of official tools by absolute or
/// PATH-resolved name with explicit argument arrays — never through a shell
/// string — so user input cannot be interpreted as shell syntax.
public enum Shell {
    public enum ShellError: Error, Equatable {
        case toolNotFound(String)
        case timedOut(String)
    }

    /// Locates an executable on the standard search path, including the
    /// Apple-silicon and Intel Homebrew prefixes that GUI-launched shells miss.
    public static func find(_ tool: String) -> String? {
        let searchPaths = [
            "/opt/homebrew/bin", "/usr/local/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ]
        for directory in searchPaths {
            let candidate = directory + "/" + tool
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Runs `tool` with `arguments`, capturing stdout and stderr.
    ///
    /// - Parameters:
    ///   - timeout: Seconds to wait before terminating the process. Slow but
    ///     legitimate commands like `brew doctor` need a generous default.
    @discardableResult
    public static func run(
        _ tool: String,
        _ arguments: [String],
        timeout: TimeInterval = 120
    ) throws -> ShellResult {
        let executable: String
        if tool.hasPrefix("/") {
            executable = tool
        } else if let found = find(tool) {
            executable = found
        } else {
            throw ShellError.toolNotFound(tool)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()

        // Drain pipes on background threads so a chatty tool cannot deadlock
        // against a full pipe buffer while we wait for exit.
        let stdoutBox = DrainBox()
        let stderrBox = DrainBox()
        let drainGroup = DispatchGroup()
        drainGroup.enter()
        DispatchQueue.global().async {
            stdoutBox.store(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            drainGroup.leave()
        }
        drainGroup.enter()
        DispatchQueue.global().async {
            stderrBox.store(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            drainGroup.leave()
        }

        let deadline = Date(timeIntervalSinceNow: timeout)
        while process.isRunning, Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            throw ShellError.timedOut(tool)
        }
        drainGroup.wait()

        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutBox.take(), encoding: .utf8) ?? "",
            stderr: String(data: stderrBox.take(), encoding: .utf8) ?? ""
        )
    }

    /// Lock-guarded buffer for pipe draining across threads.
    private final class DrainBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func store(_ value: Data) {
            lock.lock()
            data = value
            lock.unlock()
        }

        func take() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    /// Convenience: runs the tool and returns trimmed stdout on success, or
    /// `nil` when the tool is missing, fails, or times out. For probes where
    /// any failure just means "not available".
    public static func output(_ tool: String, _ arguments: [String], timeout: TimeInterval = 120) -> String? {
        guard let result = try? run(tool, arguments, timeout: timeout), result.succeeded else {
            return nil
        }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
