import Darwin
import Testing

/// Entry point for `swift run maclovin-tests`.
///
/// Runs the swift-testing suite compiled into this executable and exits with
/// the standard SwiftPM test exit code (0 on success, 1 on failure).
@main
struct TestMain {
    static func main() async {
        exit(await Testing.__swiftPMEntryPoint() as CInt)
    }
}
