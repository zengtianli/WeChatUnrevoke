import Foundation

/// The window and its companion command use this exact configuration allowlist
/// and update-channel decision. Local paths and protection/permission state stay
/// on this Mac and are never part of a configuration transfer.
enum ProductLifecycle {
    static let productID = "io.github.zengtianli.unrevoke"
    static let name = "WeChatUnrevoke"
    static let portableKeys = ["variant", "autoRepatch"]

    /// The app and its companion command share one preference domain. The command reaches it
    /// as a suite; inside the app that domain is the process's own, and `UserDefaults(suiteName:)`
    /// returns nil for a process's own bundle identifier — there `.standard` *is* that domain.
    static func makeConfiguration(defaults: UserDefaults? = nil) -> AppConfiguration {
        AppConfiguration(productID: productID, defaultsKeys: portableKeys,
                         defaults: defaults ?? UserDefaults(suiteName: productID) ?? .standard)
    }

    static func updateSource(bundle: Bundle = .main) -> AppUpdateSource {
        if bundle.object(forInfoDictionaryKey: "AppLifecycleUpdateChannel") as? String == "personal" {
            return .privateCloud(channel: "personal")
        }
        return .github(repository: "zengtianli/WeChatUnrevoke")
    }
}
