import Foundation

/// The window and its companion command use this exact configuration allowlist
/// and update-channel decision. Local paths and protection/permission state stay
/// on this Mac and are never part of a configuration transfer.
enum ProductLifecycle {
    static let productID = "io.github.zengtianli.unrevoke"
    static let name = "WeChatUnrevoke"
    static let portableKeys = ["variant", "autoRepatch"]

    static func makeConfiguration(defaults: UserDefaults? = nil) -> AppConfiguration {
        AppConfiguration(productID: productID, defaultsKeys: portableKeys,
                         defaults: defaults ?? UserDefaults(suiteName: productID)!)
    }

    static func updateSource(bundle: Bundle = .main) -> AppUpdateSource {
        if bundle.object(forInfoDictionaryKey: "AppLifecycleUpdateChannel") as? String == "personal" {
            return .privateCloud(channel: "personal")
        }
        return .github(repository: "zengtianli/WeChatUnrevoke")
    }
}
