import Foundation
import CryptoKit

// =============================================================================
// Engine — 内嵌 `wechattweak` 命令行的薄封装
//
// 为什么是「调二进制」而不是「链库」：打补丁在 4.1.13 之前的微信包上需要 root，
// GUI 进程自己提不了权，本来就必须起一个独立进程。既然如此就只保留一份引擎，
// 由 CLI 承担全部字节读写与重签；Swift 这一层零业务逻辑。
//   引擎 SSOT = https://github.com/zengtianli/WeChatTweak
//   构建期由 build.sh 拷进 Unrevoke.app/Contents/Resources/wechattweak
//
// 进程处理的坑（蒸馏自 ssot-console BackendClient，每条都真踩过）：
//   · GUI app 只继承 launchd 极简 PATH → 显式补 PATH
//   · 子进程输出 >64KB 管道塞死 → stdout/stderr 各自后台队列并发 drain
//   · 超时 → terminate + 抛人话；Task 取消 → terminate + CancellationError
// =============================================================================

enum EngineError: LocalizedError {
    case cliMissing
    case launchFailed(String)
    case failed(code: Int32, output: String)
    case writePermissionDenied(output: String)
    /// 引擎已判明写入被拒的原因（`Write blocked: <codes>`）。
    case writeBlocked(codes: [String], output: String)
    case decodeFailed(String, raw: String)
    case timeout(TimeInterval)
    case authCanceled

    var errorDescription: String? {
        switch self {
        case .cliMissing:
            return L.err_cliMissing
        case .launchFailed(let m):
            return L.err_launch(m)
        case .failed(_, let output):
            // 引擎的错误信息本身就是写给人看的（含下一步命令），原样透出比包一层强。
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        case .writePermissionDenied:
            return L.err_writePermissionDenied
        case .writeBlocked(let codes, _):
            return L.err_writeBlocked(codes)
        case .decodeFailed(let m, let raw):
            return L.err_decode(m, String(raw.prefix(300)))
        case .timeout(let t):
            return L.err_timeout(Int(t))
        case .authCanceled:
            return L.err_authCanceled
        }
    }

    /// Keep the original CLI/osascript output in diagnostics even when the UI
    /// replaces it with recovery instructions.
    var diagnosticOutput: String {
        switch self {
        case .failed(_, let output), .writePermissionDenied(let output), .writeBlocked(_, let output):
            return output
        default:
            return localizedDescription
        }
    }

    static func writeFailure(code: Int32, output: String) -> EngineError {
        // 新引擎在写入被拒后自己判明原因并打印 `Write blocked: a,b`；有这一行就照它说，
        // 不在这里猜。旧引擎没有这一行，回落到下面的逐项排查文案。
        if let line = output.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { $0.hasPrefix("Write blocked: ") }) {
            let codes = line.dropFirst("Write blocked: ".count).split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !codes.isEmpty { return .writeBlocked(codes: codes, output: output) }
        }
        // A permission error alone cannot distinguish App Management from file
        // ownership, ACLs or locked files. Offer checks, not a claimed TCC verdict.
        let text = output.lowercased().replacingOccurrences(of: "’", with: "'")
        // Error codes first: 513 = no write permission, 257 = no read permission.
        // The engine prints only the localized description, so wording is the
        // fallback. Foundation words the same 513 differently per operation:
        // "permission to save" (write/create), "couldn't be copied/moved ...
        // permission to access" (copy/move/remove), "permission to view" (read).
        let denied = text.range(of: #"nscocoaerrordomain\s+code\s*=\s*(?:513|257)\b"#,
                                options: .regularExpression) != nil
            || ["permission denied", "operation not permitted",
                "don't have permission", "do not have permission"]
                .contains { text.contains($0) }
            || text.range(of: #"(?:没有|沒有)[^\n]*(?:权限|權限)"#,
                          options: .regularExpression) != nil
        return denied ? .writePermissionDenied(output: output) : .failed(code: code, output: output)
    }
}

/// 引用盒：并发 drain 队列把数据交还 waiter 闭包。每个盒只被一个 drain task 写，
/// waiter 在 `group.wait()` 建立 happens-before 之后才读。
private final class DataBox: @unchecked Sendable { var data = Data() }
private final class FlagBox: @unchecked Sendable { var on = false }

/// 拉一次线上补丁库的结果。
enum ConfigRefresh: Equatable {
    case updated
    case unchanged
    case failed(String)

    var diagnostic: String {
        switch self {
        case .updated: return "updated"
        case .unchanged: return "unchanged"
        case .failed(let reason): return "failed: " + reason
        }
    }
}

actor Engine {
    static let wechatBundleID = "com.tencent.xinWeChat"
    static let defaultWeChatPath = "/Applications/WeChat.app"

    /// 要操作的 WeChat.app。默认 /Applications，可用
    ///   defaults write io.github.zengtianli.unrevoke weChatPath /path/to/WeChat.app
    /// 指向一份副本 —— 这是为了能对着副本把「打补丁 / 还原」整条路真跑一遍，
    /// 而不是拿正在用的微信当试验田。没有这个接缝，写入路径就只能靠「看着对」。
    static var weChatPath: String {
        UserDefaults.standard.string(forKey: "weChatPath") ?? defaultWeChatPath
    }

    /// 上游 config.json 的权威地址。新微信版本发布后我往这里追加补丁点，
    /// 已装的 Unrevoke 下次启动就能认新版本 —— **不需要用户更新 app**。
    /// 这是「自动跟版」真正的实现处，不是 UI 上的一句话。
    static let remoteConfigURL = URL(string: "https://raw.githubusercontent.com/zengtianli/WeChatTweak/refs/heads/master/config.json")!

    private static let timeoutRead: TimeInterval = 60
    private static let timeoutWrite: TimeInterval = 600   // 重签 225 个代码对象要几十秒

    // MARK: - 位置

    /// 内嵌的 CLI。缺了就明确报错 —— 回落到 PATH 上「碰巧装过的那个 wechattweak」
    /// 会拿一个版本未知的引擎去写别人的微信，比报错危险得多。
    static func cliURL() throws -> URL {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("wechattweak"),
              FileManager.default.isExecutableFile(atPath: url.path) else {
            throw EngineError.cliMissing
        }
        return url
    }

    /// 缓存的 config.json：优先用联网拉到的最新版，拉不到就用随 app 打包的那份。
    /// 测试接缝同 weChatPath：`defaults write … supportDirectory /tmp/x` 让跟版缓存落在临时目录，
    /// 不碰真实的 ~/Library/Application Support/Unrevoke。
    static var supportDirectory: URL {
        if let custom = UserDefaults.standard.string(forKey: "supportDirectory") {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Unrevoke", isDirectory: true)
    }
    static var cachedConfigURL: URL { supportDirectory.appendingPathComponent("config.json") }
    static var bundledConfigURL: URL? { Bundle.main.resourceURL?.appendingPathComponent("config.json") }

    /// 当前该用哪份 config.json。缓存存在且能解析就用缓存，否则用内置。
    static func activeConfigURL() -> URL? {
        if let data = try? Data(contentsOf: cachedConfigURL),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return cachedConfigURL
        }
        return bundledConfigURL
    }

    // MARK: - 跟版

    /// 拉一次最新 config.json 存进缓存。
    /// fail-closed：拿到的东西解不成 JSON、或条目数比现有的还少，就**不覆盖**——
    /// 半截响应（代理返回的登录页、断流）写进去会让所有版本一起「不支持」。
    /// 失败带原因返回：「没拉到」和「拉到了但没新东西」混成一个 false，下载失败的人
    /// 只会看到「还没收录」，也没人知道是哪一步断的（#12）。
    /// 内容变了就算更新，不看条目数：同样多的条目里改了补丁点，也要重新体检。
    func refreshConfig() async -> ConfigRefresh {
        var request = URLRequest(url: Engine.remoteConfigURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let data: Data
        do {
            let (body, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed("not an HTTP response") }
            guard http.statusCode == 200 else { return .failed("HTTP \(http.statusCode)") }
            data = body
        } catch let error as URLError {
            return .failed("network error \(error.code.rawValue): \(error.localizedDescription)")
        } catch {
            return .failed(error.localizedDescription)
        }
        guard let incoming = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !incoming.isEmpty else {
            return .failed("response is not a patch list (\(data.count) bytes)")
        }
        let current = Engine.activeConfigURL().flatMap { try? Data(contentsOf: $0) }
        let currentCount = current.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }?.count ?? 0
        guard incoming.count >= currentCount else {
            return .failed("response lists \(incoming.count) builds, fewer than the \(currentCount) in use")
        }
        guard data != current else { return .unchanged }
        do {
            try FileManager.default.createDirectory(at: Engine.supportDirectory, withIntermediateDirectories: true)
            try data.write(to: Engine.cachedConfigURL, options: .atomic)
        } catch {
            return .failed("cannot save: \(error.localizedDescription)")
        }
        return .updated
    }

    /// 诊断里写清这次体检实际用的是哪份补丁库：来源、条目数、SHA256 前 12 位、有没有这个 build。
    /// 只看源码里的 config.json 判断不了用户手上那份。
    static func activeConfigSummary(build: String?) -> String {
        guard let url = activeConfigURL(), let data = try? Data(contentsOf: url) else { return "none" }
        let source = url == cachedConfigURL ? "downloaded" : "bundled"
        let entries = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(12)
        let listed = build.map { b in entries.contains { ($0["version"] as? String) == b } ? "yes" : "no" } ?? "n/a"
        return "\(source)  builds: \(entries.count)  sha256: \(digest)  lists build: \(listed)"
    }

    // MARK: - 子命令

    func doctor(app: String = Engine.weChatPath) async throws -> DoctorStatus {
        let output = try await run(["doctor", "-a", app, "--json"] + configArgs(), timeout: Engine.timeoutRead)
        guard let data = output.data(using: .utf8) else {
            throw EngineError.decodeFailed("empty", raw: output)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(DoctorStatus.self, from: data)
        } catch {
            throw EngineError.decodeFailed(error.localizedDescription, raw: output)
        }
    }

    /// The engine applies anti-recall and the update block independently and exits 0 when
    /// either went in; the fresh doctor afterwards says exactly which.
    func patch(app: String = Engine.weChatPath, variant: PatchVariant, admin: Bool) async throws -> String {
        try await runWrite(["patch", "-a", app, "--variant", variant.rawValue, "--auto-locate"] + configArgs(),
                      admin: admin)
    }

    func restore(app: String = Engine.weChatPath, admin: Bool) async throws -> String {
        try await runWrite(["restore", "-a", app] + configArgs(), admin: admin)
    }

    private func runWrite(_ args: [String], admin: Bool) async throws -> String {
        do {
            return try await run(args, timeout: Engine.timeoutWrite, admin: admin)
        } catch let EngineError.failed(code, output) {
            throw EngineError.writeFailure(code: code, output: output)
        }
    }

    private func configArgs() -> [String] {
        guard let url = Engine.activeConfigURL(), FileManager.default.fileExists(atPath: url.path) else { return [] }
        return ["-c", url.path]
    }

    // MARK: - 执行

    private func run(_ args: [String], timeout: TimeInterval, admin: Bool = false) async throws -> String {
        let cli = try Engine.cliURL()
        if admin {
            return try await runPrivileged(cli: cli, args: args, timeout: timeout)
        }
        return try await runProcess(executable: URL(fileURLWithPath: "/usr/bin/env"),
                                    arguments: [cli.path] + args, timeout: timeout)
    }

    /// 提权执行：osascript 的 `with administrator privileges` 弹系统那个标准授权框。
    /// 没有装特权 helper —— 一个「只在用户按下按钮那一刻存在」的授权，比常驻 root 服务
    /// 的攻击面小得多，代价是每次都要输一次密码（只有 4.1.13 之前的包才走到这里）。
    private func runPrivileged(cli: URL, args: [String], timeout: TimeInterval) async throws -> String {
        let command = ([cli.path] + args).map(Engine.shellQuote).joined(separator: " ") + " 2>&1"
        let script = "do shell script \"\(Engine.appleScriptQuote(command))\" with administrator privileges"
        do {
            return try await runProcess(executable: URL(fileURLWithPath: "/usr/bin/osascript"),
                                        arguments: ["-e", script], timeout: timeout)
        } catch let EngineError.failed(code, output) {
            // 用户点了「取消」→ osascript 报 -128。这不是失败，是用户的决定。
            if output.contains("-128") || output.contains("User canceled") {
                throw EngineError.authCanceled
            }
            throw EngineError.failed(code: code, output: output)
        }
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptQuote(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func runProcess(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        let extra = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        env["PATH"] = (extra + [env["PATH"] ?? ""]).joined(separator: ":")
        process.environment = env

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let canceled = FlagBox(), timedOut = FlagBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                let queue = DispatchQueue(label: "io.github.zengtianli.unrevoke.engine-io", attributes: .concurrent)
                let group = DispatchGroup()
                let outBox = DataBox(), errBox = DataBox()

                group.enter()
                group.enter()
                // Install before launch: a short-lived child can exit before a
                // background waitUntilExit run loop starts observing it.
                process.terminationHandler = { finished in
                    group.notify(queue: queue) {
                        finished.terminationHandler = nil
                        if canceled.on { cont.resume(throwing: CancellationError()); return }
                        if timedOut.on { cont.resume(throwing: EngineError.timeout(timeout)); return }
                        let out = String(decoding: outBox.data, as: UTF8.self)
                        let err = String(decoding: errBox.data, as: UTF8.self)
                        if finished.terminationStatus == 0 {
                            cont.resume(returning: out)
                        } else {
                            cont.resume(throwing: EngineError.failed(
                                code: finished.terminationStatus,
                                output: err.isEmpty ? out : (out.isEmpty ? err : out + "\n" + err)))
                        }
                    }
                }
                do { try process.run() } catch {
                    process.terminationHandler = nil
                    group.leave(); group.leave()
                    cont.resume(throwing: EngineError.launchFailed(error.localizedDescription)); return
                }
                queue.async { outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                queue.async { errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }

                queue.asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning { timedOut.on = true; process.terminate() }
                }
            }
        } onCancel: {
            canceled.on = true
            if process.isRunning { process.terminate() }
        }
    }
}
