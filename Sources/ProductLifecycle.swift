import Foundation

/// The window and its companion command use this exact configuration allowlist
/// and update-channel decision. Local paths and protection/permission state stay
/// on this Mac and are never part of a configuration transfer.
enum ProductLifecycle {
    static let productID = "io.github.zengtianli.unrevoke"
    static let name = "WeChatUnrevoke"
    static let portableKeys = ["variant", "autoRepatch", "appUpdateOptions"] + AppShortcuts.portableKeys

    static func preferences() -> UserDefaults {
        let env = ProcessInfo.processInfo.environment
        if let support = env["APP_LIFECYCLE_SUPPORT_DIR"] {
            guard !support.isEmpty, let suite = env["UNREVOKE_LIFECYCLE_SUITE"],
                  suite.hasPrefix(productID + ".accept."), suite != productID else {
                fatalError("Isolated lifecycle requires its own preference suite and support directory")
            }
            if suite == Bundle.main.bundleIdentifier { return .standard }
            guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Isolated preference suite unavailable") }
            return defaults
        }
        return UserDefaults(suiteName: productID) ?? .standard
    }

    /// The app and its companion command share one preference domain. The command reaches it
    /// as a suite; inside the app that domain is the process's own, and `UserDefaults(suiteName:)`
    /// returns nil for a process's own bundle identifier — there `.standard` *is* that domain.
    static func makeConfiguration(defaults: UserDefaults? = nil) -> AppConfiguration {
        AppConfiguration(productID: productID, defaultsKeys: portableKeys,
                         defaults: defaults ?? preferences())
    }

    static func updateSource(bundle: Bundle = .main) -> AppUpdateSource {
        let env = ProcessInfo.processInfo.environment
        if env["APP_LIFECYCLE_SUPPORT_DIR"] != nil,
           (bundle.bundleIdentifier ?? "").hasPrefix(productID + ".accept."),
           env["UNREVOKE_TEST_UPDATE_CHANNEL"] == "test" {
            return .privateCloud(channel: "test")
        }
        if bundle.object(forInfoDictionaryKey: "AppLifecycleUpdateChannel") as? String == "personal" {
            return .privateCloud(channel: "personal")
        }
        return .github(repository: "zengtianli/WeChatUnrevoke")
    }

    @MainActor
    static func commandMode(_ words: [String]) -> Int32? {
        if AppLifecycleCLI.handles(words.first) {
            return AppLifecycleCLI.run(words, product: .init(command: "WeChatUnrevoke", name: name,
                configuration: makeConfiguration(), updateSource: updateSource()))
        }
        return ProductSettings.commandMode(words)
    }
}
