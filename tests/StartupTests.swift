import AppKit
import SwiftUI

/// Exercise production App construction before AppKit has created NSApp.
/// No App.main/run, window, activation, preferences, network or input actions.
@main
@MainActor
struct StartupTests {
    static func main() {
        precondition(NSApp == nil, "The regression requires a fresh pre-AppKit process")
        let app = UnrevokeApp()
        withExtendedLifetime(app) {
            precondition(NSApp == nil, "App.init must not initialize AppKit or install lifecycle UI")
        }
        print("PASS: production App.init is safe before NSApp exists")
    }
}
