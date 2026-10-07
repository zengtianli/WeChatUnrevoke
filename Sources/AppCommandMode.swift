import Foundation
import ServiceManagement

/// Commands that must execute inside the real main app bundle, before SwiftUI
/// starts. No NSApplication, window, dialog or System Settings is opened here.
@MainActor
enum AppCommandMode {
    enum LoginStatus: String {
        case notRegistered, enabled, requiresApproval, notFound, unknown
    }

    /// A closure seam keeps fixture tests away from the user's login items.
    struct LoginService {
        var status: () -> LoginStatus
        var register: () throws -> Void
        var unregister: () throws -> Void

        static var mainApp: LoginService {
            LoginService(status: {
                switch SMAppService.mainApp.status {
                case .notRegistered: return .notRegistered
                case .enabled: return .enabled
                case .requiresApproval: return .requiresApproval
                case .notFound: return .notFound
                @unknown default: return .unknown
                }
            }, register: { try SMAppService.mainApp.register() },
               unregister: { try SMAppService.mainApp.unregister() })
        }
    }

    /// `arguments` excludes argv[0]. nil means this is not a command-mode launch.
    static func run(arguments: [String]) -> Int32? {
        guard arguments.first == "--login" else { return nil }
        return run(arguments: arguments, service: .mainApp, output: { print($0) })
    }

    /// Exit codes: 0 success, 1 service/readback failure, 2 usage,
    /// 3 explicit confirmation missing, 4 System Settings approval required.
    static func run(arguments: [String], service: LoginService, output: (String) -> Void) -> Int32? {
        guard arguments.first == "--login" else { return nil }
        let json = arguments.contains("--json")
        let zh = (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
        func text(_ chinese: String, _ english: String) -> String { zh ? chinese : english }
        var result: [String: Any] = ["command": "login", "changed": false,
                                     "dry_run": arguments.contains("--dry-run")]
        func finish(_ code: Int32, _ message: String, error: String? = nil) -> Int32 {
            result["ok"] = code == 0
            result["message"] = message
            if let error { result["error"] = error }
            if json {
                // The payload contains only JSON primitives owned by this command.
                let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                output(String(decoding: data, as: UTF8.self))
            } else {
                output(message)
            }
            return code
        }
        func observe(_ status: LoginStatus) {
            result["status"] = status.rawValue
            result["enabled"] = status == .enabled
            result["requires_approval"] = status == .requiresApproval
        }
        func unavailable(_ status: LoginStatus) -> Int32? {
            if status == .requiresApproval {
                result["next_step"] = text("请在系统设置 → 通用 → 登录项中允许 WeChatUnrevoke。",
                    "Allow WeChatUnrevoke in System Settings → General → Login Items.")
                return finish(4, text("登录项已登记，但仍需你在系统设置中允许。",
                    "The login item is registered but still requires your approval in System Settings."),
                    error: "requires_approval")
            }
            if status == .notFound || status == .unknown {
                return finish(1, text("无法确认本应用的登录项状态，请从完整的 App 包运行命令。",
                    "The app's login-item state is unavailable. Run this command from the complete app bundle."),
                    error: "service_unavailable")
            }
            return nil
        }

        let actions = ["status", "on", "off"]
        let flags = Array(arguments.dropFirst(2))
        guard arguments.count >= 2, actions.contains(arguments[1]),
              flags.allSatisfy({ ["--json", "--dry-run", "--yes"].contains($0) }),
              Set(flags).count == flags.count else {
            return finish(2, "Usage: --login status|on|off [--json] [--dry-run] [--yes]", error: "invalid_arguments")
        }
        let action = arguments[1]
        result["action"] = action
        let before = service.status()
        observe(before)
        let desired: LoginStatus = action == "on" ? .enabled : .notRegistered
        let changeNeeded = action != "status" && before != desired
        result["would_change"] = changeNeeded

        if action == "status" {
            if let code = unavailable(before) { return code }
            return finish(0, before == .enabled
                ? text("开机自动运行已开启。", "Launch at login is enabled.")
                : text("开机自动运行已关闭。", "Launch at login is disabled."))
        }
        if arguments.contains("--dry-run") {
            if let code = unavailable(before) { return code }
            return finish(0, changeNeeded
                ? text("预览完成；将修改登录项，当前未作更改。", "Preview complete; the login item would change. Nothing was changed.")
                : text("预览完成；登录项已经符合请求，当前未作更改。", "Preview complete; the login item already matches. Nothing was changed."))
        }
        guard arguments.contains("--yes") else {
            result["confirmation_required"] = true
            return finish(3, text("修改登录项需要显式确认；加 --yes 执行，或用 --dry-run 预览。",
                "Changing login items requires explicit confirmation. Add --yes to apply or --dry-run to preview."),
                error: "confirmation_required")
        }
        // Disabling can withdraw a pending registration. Enabling a registration
        // that awaits approval cannot substitute for the user's Settings choice.
        if before == .notFound || before == .unknown || (action == "on" && before == .requiresApproval) {
            return unavailable(before)
        }
        if !changeNeeded {
            return finish(0, text("登录项已经符合请求，无需更改。", "The login item already matches; no change is needed."))
        }

        result["previous_status"] = before.rawValue
        do {
            if action == "on" { try service.register() } else { try service.unregister() }
        } catch {
            // Even an API error may follow a partial change. Always read back.
            let after = service.status()
            observe(after)
            result["changed"] = after != before
            let failure = error as NSError
            result["service_error"] = ["domain": failure.domain, "code": failure.code,
                                       "message": failure.localizedDescription]
            if after == .requiresApproval { return unavailable(after) }
            return finish(1, text("登录项操作失败；结果已重新读取，请检查错误详情。",
                "The login-item operation failed; its state was read back. Check the error details."), error: "operation_failed")
        }
        let after = service.status()
        observe(after)
        result["changed"] = after != before
        if let code = unavailable(after) { return code }
        guard after == desired else {
            return finish(1, text("操作已返回，但登录项尚未达到请求状态；请重新查询。",
                "The operation returned, but the login item does not yet match the request. Check its status again."),
                error: "state_mismatch")
        }
        return finish(0, action == "on"
            ? text("开机自动运行已开启。", "Launch at login is enabled.")
            : text("开机自动运行已关闭。", "Launch at login is disabled."))
    }
}
