import Foundation

/// Only the new portable-settings subcommands use the shared lifecycle layer.
/// Bare `config`, `config --json`, and `config refresh` remain patch-library API.
enum UnrevokeLifecycle {
    static func handles(_ arguments: [String]) -> Bool {
        guard let verb = arguments.first else { return false }
        if verb == "update" { return true }
        guard verb == "config",
              let sub = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) else { return false }
        return ["status", "export", "import", "sync"].contains(sub)
    }

    struct HostError: LocalizedError {
        var errorDescription: String? { "unrevoke 必须位于同包的 Contents/Resources/bin；无法核对主 App 身份。" }
    }

    static func hostBundle(executableURL: URL) throws -> Bundle {
        let executable = executableURL.resolvingSymlinksInPath().standardizedFileURL
        let bin = executable.deletingLastPathComponent()
        let resources = bin.deletingLastPathComponent()
        let contents = resources.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard bin.lastPathComponent == "bin", resources.lastPathComponent == "Resources",
              contents.lastPathComponent == "Contents", app.pathExtension == "app",
              let bundle = Bundle(url: app), bundle.bundleIdentifier == ProductLifecycle.productID else {
            throw HostError()
        }
        return bundle
    }

    static func makeProduct(executableURL: URL, defaultsDomain: String? = nil) throws -> AppLifecycleCLI.Product {
        let bundle = try hostBundle(executableURL: executableURL)
        let domain = defaultsDomain ?? ProductLifecycle.productID
        guard !domain.isEmpty, let defaults = UserDefaults(suiteName: domain) else { throw HostError() }
        var product = AppLifecycleCLI.Product(command: "unrevoke", name: ProductLifecycle.name,
            configuration: ProductLifecycle.makeConfiguration(defaults: defaults),
            updateSource: ProductLifecycle.updateSource(bundle: bundle), bundle: bundle)
        // A fixture never inspects or notifies the real window process.
        if ProcessInfo.processInfo.environment["APP_LIFECYCLE_SUPPORT_DIR"] != nil {
            product.runningApp = { [] }
        }
        return product
    }

    /// Call on the main thread before the legacy dispatcher switches on its verb.
    static func run(_ arguments: [String], executableURL: URL, defaultsDomain: String? = nil) -> Int32 {
        do {
            return AppLifecycleCLI.run(arguments,
                product: try makeProduct(executableURL: executableURL, defaultsDomain: defaultsDomain))
        } catch {
            if arguments.contains("--json") {
                let value: [String: Any] = ["ok": false, "command": arguments.prefix(2).joined(separator: " "),
                    "error": ["code": "host_bundle_missing", "message": error.localizedDescription]]
                if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
                    FileHandle.standardOutput.write(data + Data("\n".utf8))
                }
            } else {
                FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            }
            return 64
        }
    }
}
