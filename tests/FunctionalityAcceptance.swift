import Foundation
import Darwin

/// Real AppModel/Engine acceptance; every write is restricted to the disposable sibling bundle.
@main
struct FunctionalityAcceptance {
    struct CheckError: LocalizedError {
        let message: String
        let unavailable: Bool
        var errorDescription: String? { message }
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String,
                        unavailable: Bool = false) throws {
        guard condition() else { throw CheckError(message: message, unavailable: unavailable) }
    }

    @MainActor static func main() async {
        do { try await check() }
        catch {
            print(error.localizedDescription)
            exit((error as? CheckError)?.unavailable == true ? 78 : 1)
        }
    }

    @MainActor static func check() async throws {
        let arguments = CommandLine.arguments
        try require(arguments.count == 3, "Expected isolated copy and result file.")
        guard let identifier = Bundle.main.bundleIdentifier else {
            throw CheckError(message: "Missing isolated bundle identifier.", unavailable: false)
        }
        try require(identifier.hasPrefix("io.github.zengtianli.unrevoke.accept.functionality."),
                    "Refusing production preference domain.")
        let copy = URL(fileURLWithPath: arguments[1]).standardizedFileURL.resolvingSymlinksInPath()
        let workspace = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        try require(copy.deletingLastPathComponent() == workspace && copy.lastPathComponent == "WeChat.app",
                    "Refusing a target outside the isolated acceptance workspace.")
        try require(copy.path != Engine.defaultWeChatPath, "Refusing the installed WeChat bundle.")
        let defaults = UserDefaults.standard
        defaults.removePersistentDomain(forName: identifier)
        defaults.set(copy.path, forKey: "weChatPath")
        defaults.set(false, forKey: "autoRepatch")
        defaults.set(false, forKey: "everProtected")
        defaults.set(PatchVariant.keeptip.rawValue, forKey: "variant")
        defer { defaults.removePersistentDomain(forName: identifier) }
        try require(Engine.weChatPath == copy.path, "Copy preference was not isolated.")

        // Independent readback launches the real engine directly; AppModel status alone is insufficient.
        func doctor() throws -> [String: Any] {
            let process = Process()
            process.executableURL = try Engine.cliURL()
            var args = ["doctor", "-a", copy.path, "--json"]
            if let config = Engine.activeConfigURL() { args += ["-c", config.path] }
            process.arguments = args
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            try require(process.terminationStatus == 0, "Independent doctor failed.")
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CheckError(message: "Invalid independent doctor output.", unavailable: false)
            }
            return decoded
        }
        func writable(_ state: [String: Any]) throws {
            try require(state["running"] as? Bool == false, "Disposable WeChat is running; no quit attempted.", unavailable: true)
            try require(state["writable"] as? Bool == true, "Disposable WeChat requires administrator access; no authorization attempted.", unavailable: true)
            try require(state["config_known"] as? Bool == true, "Current WeChat build is absent from the available patch config.", unavailable: true)
            try require(state["entitlements_ok"] as? Bool == true, "Source WeChat has invalid entitlements; supply a healthy bundle.", unavailable: true)
        }
        let initial = try doctor()
        try writable(initial)
        let entitlementCount = initial["entitlement_key_count"] as? Int
        var confirmations = 0
        let model = AppModel(confirmAction: { title, _, _ in
            confirmations += 1
            // Restore is the only allowed confirmation. Never authorize quitting a live application.
            return title == L.flow_restoreConfirm
        })
        await model.refresh()
        try require(model.status != nil && model.status?.needsAdmin == false && model.status?.running == false,
                    "AppModel did not load a writable, stopped copy.", unavailable: true)
        func complete(_ expected: Set<String>, _ phase: String) throws -> [String: Any] {
            if model.errorMessage != nil {
                let denied = model.errorMessage == L.err_writePermissionDenied
                throw CheckError(message: denied
                    ? "macOS denied modifications to the disposable WeChat copy during \(phase). Run this fixed acceptor from an authorized terminal after checking App Management and copy permissions."
                    : "AppModel \(phase) failed: \(model.lastLog)", unavailable: denied)
            }
            let state = try doctor()
            let overall = state["overall"] as? String ?? "missing"
            try require(expected.contains(overall), "Independent doctor found \(overall) after \(phase).")
            try require(model.status?.overall.rawValue == overall, "Post-write AppModel did not refresh the actual \(phase) state.")
            try require(!model.isBusy, "AppModel remained busy after \(phase).")
            try require(state["entitlements_ok"] as? Bool == true, "Entitlements invalid after \(phase).")
            try require(state["entitlement_key_count"] as? Int == entitlementCount,
                        "Entitlement count changed after \(phase).")
            return state
        }

        await model.restoreNow()
        _ = try complete(["unprotected"], "baseline restore")
        try writable(try doctor())
        await model.protectNow()
        let patched = try complete(["protected", "antiRevokeOnly"], "patch")
        try require(patched["anti_revoke_keeptip"] as? String == "patched", "Default keep-tip variant was not applied.")
        try require(defaults.bool(forKey: "everProtected"), "Successful patch did not set everProtected.")
        try writable(try doctor())
        await model.restoreNow()
        let restored = try complete(["unprotected"], "final restore")
        try require(!defaults.bool(forKey: "everProtected"), "Restore did not clear everProtected.")
        try require(confirmations == 2, "Unexpected confirmation path was invoked.")
        let report: [String: Any] = [
            "source_build": initial["build"] ?? "unknown",
            "patched_overall": patched["overall"] ?? "unknown",
            "anti_revoke_keeptip": patched["anti_revoke_keeptip"] ?? "unknown",
            "update_block": patched["update_block"] ?? "unknown",
            "restored_overall": restored["overall"] ?? "unknown",
            "entitlements_preserved": true,
            "app_model_post_write_refresh": true,
            "isolated_preferences": true,
            "confirmation_count": confirmations,
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: arguments[2]))
        print("PASS: actual AppModel patch/restore and independent engine readback.")
    }
}
