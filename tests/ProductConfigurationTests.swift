import Foundation

/// The shipped app's main bundle identifier *is* the product identifier. `UserDefaults(suiteName:)`
/// returns nil for a process's own bundle identifier, so the configuration must be built in a
/// bundle that carries the real identifier — a test bundle with any other identifier never sees it.
/// Construction only: no window, no AppKit, no preference or file is written.
@main
@MainActor
struct ProductConfigurationTests {
    static func main() {
        precondition(Bundle.main.bundleIdentifier == ProductLifecycle.productID,
                     "The regression requires the product's own bundle identifier")
        let configuration = ProductLifecycle.makeConfiguration()
        withExtendedLifetime(configuration) {}
        print("PASS: configuration is built inside the product's own bundle identifier")
    }
}
