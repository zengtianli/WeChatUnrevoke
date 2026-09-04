import Foundation

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
        case .decodeFailed(let m, let raw):
            return L.err_decode(m, String(raw.prefix(300)))
        case .timeout(let t):
            return L.err_timeout(Int(t))
        case .authCanceled:
            return L.err_authCanceled
        }
    }
}

/// 引用盒：并发 drain 队列把数据交还 waiter 闭包。每个盒只被一个 drain task 写，
/// waiter 在 `group.wait()` 建立 happens-before 之后才读。
private final class DataBox: @unchecked Sendable { var data = Data() }
private final class FlagBox: @unchecked Sendable { var on = false }

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
    static var supportDirectory: URL {
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
    /// - Returns: 真的更新了返回 true。
    @discardableResult
    func refreshConfig() async -> Bool {
        do {
            var request = URLRequest(url: Engine.remoteConfigURL)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            guard let incoming = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  !incoming.isEmpty else { return false }

            let currentCount: Int = {
                guard let url = Engine.activeConfigURL(),
                      let old = try? Data(contentsOf: url),
                      let arr = try? JSONSerialization.jsonObject(with: old) as? [[String: Any]] else { return 0 }
                return arr.count
            }()
            guard incoming.count >= currentCount else { return false }

            try FileManager.default.createDirectory(at: Engine.supportDirectory, withIntermediateDirectories: true)
            try data.write(to: Engine.cachedConfigURL, options: .atomic)
            return incoming.count > currentCount
        } catch {
            return false
        }
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

    func patch(app: String = Engine.weChatPath, variant: PatchVariant, admin: Bool) async throws -> String {
        try await run(["patch", "-a", app, "--variant", variant.rawValue, "--auto-locate"] + configArgs(),
                      timeout: Engine.timeoutWrite, admin: admin)
    }

    func restore(app: String = Engine.weChatPath, admin: Bool) async throws -> String {
        try await run(["restore", "-a", app] + configArgs(), timeout: Engine.timeoutWrite, admin: admin)
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

                do { try process.run() } catch {
                    cont.resume(throwing: EngineError.launchFailed(error.localizedDescription)); return
                }

                group.enter()
                queue.async { outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                group.enter()
                queue.async { errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }

                queue.asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning { timedOut.on = true; process.terminate() }
                }

                queue.async {
                    process.waitUntilExit()
                    group.wait()
                    if canceled.on { cont.resume(throwing: CancellationError()); return }
                    if timedOut.on { cont.resume(throwing: EngineError.timeout(timeout)); return }
                    let out = String(decoding: outBox.data, as: UTF8.self)
                    let err = String(decoding: errBox.data, as: UTF8.self)
                    if process.terminationStatus == 0 {
                        cont.resume(returning: out)
                    } else {
                        cont.resume(throwing: EngineError.failed(
                            code: process.terminationStatus,
                            output: err.isEmpty ? out : (out.isEmpty ? err : out + "\n" + err)))
                    }
                }
            }
        } onCancel: {
            canceled.on = true
            if process.isRunning { process.terminate() }
        }
    }
}
