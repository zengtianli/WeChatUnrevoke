// unrevoke — WeChatUnrevoke.app 内的命令行（Contents/Resources/bin/unrevoke）。界面给人用，命令行给 Agent 用。
//
// 与界面共用同一个引擎、同一份补丁库、同一个偏好域；判决只由引擎算，这里不重算：
//   unrevoke doctor|versions   → Contents/Resources/wechattweak（GUI 用的同一个引擎）
//   unrevoke patch|restore     → 同一个引擎、与 GUI Engine.patch/restore 相同的参数；前提（按判决给按钮、
//                                微信没在跑、要不要管理员）照 GUI 的规则把门，写完照 GUI 重新体检、记偏好
//   unrevoke settings|config   → GUI 的偏好域与补丁库缓存（同键名、同缺省值、同 fail-closed 规则）
// 与 GUI 源码（~/Apps/unrevoke/Sources/Engine.swift、ViewModel.swift、ContentView.swift）的对应由
// tests/test_dispatcher.py 钉住：参数、键名、补丁库规则或按钮门槛一边改了另一边没跟，测试就失败。
// 由 build.sh 编译进包（与 GUI 共用 Sources/ 里的生命周期与写入记录源码）。
import Darwin
import Foundation

let fm = FileManager.default
let env = ProcessInfo.processInfo.environment

/// 退出码（README「命令行」一节同表）。
enum Code {
    static let ok: Int32 = 0
    static let failed: Int32 = 1
    static let usage: Int32 = 2
    static let noApp: Int32 = 64        // -a 路径不存在（与引擎同码）
    static let refused: Int32 = 65      // 当前判决或目标不允许（界面此时也不给这个按钮）
    static let unavailable: Int32 = 69  // 包内缺件
    static let busy: Int32 = 75         // 微信或界面正在运行、另一个写入在进行
    static let permission: Int32 = 77   // 需要管理员，或 macOS 拒绝修改
}

func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
}

func warn(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

func die(_ message: String, _ code: Int32 = Code.usage) -> Never {
    warn(message)
    exit(code)
}

/// 真实可执行路径（跟随 ~/.local/bin 的软链），据此找同包资源。
func executablePath() -> String {
    var size: UInt32 = 0
    _NSGetExecutablePath(nil, &size)
    var buffer = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buffer, &size) == 0, let real = realpath(buffer, nil) else {
        die("unrevoke: 无法确定自身位置")
    }
    defer { free(real) }
    return String(cString: real)
}

let resources = ((executablePath() as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
let contents = (resources as NSString).deletingLastPathComponent
let engine = resources + "/wechattweak"
let home = NSHomeDirectory()

func isExecutable(_ path: String) -> Bool { fm.isExecutableFile(atPath: path) }

// MARK: - 子进程

final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

struct RunResult {
    var code: Int32
    var out: String
    var err: String
    var timedOut = false
    var combined: String { [out, err].filter { !$0.isEmpty }.joined(separator: "\n") }
}

/// 起子进程并同时读 stdout/stderr（任一边超过管道缓冲都不会卡死）；stdin 接空，`sudo -n` 永远不会等输入。
func run(_ launch: String, _ args: [String], timeout: TimeInterval? = nil,
         environment: [String: String]? = nil) -> RunResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launch)
    process.arguments = args
    if let environment { process.environment = environment }
    let outPipe = Pipe(), errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    process.standardInput = FileHandle.nullDevice
    do { try process.run() } catch {
        return RunResult(code: 127, out: "", err: error.localizedDescription)
    }
    let out = Box(Data()), err = Box(Data()), timedOut = Box(false)
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async { out.value = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
    group.enter()
    DispatchQueue.global().async { err.value = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
    if let timeout {
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if process.isRunning { timedOut.value = true; process.terminate() }
        }
    }
    process.waitUntilExit()
    group.wait()
    return RunResult(code: process.terminationStatus, out: String(decoding: out.value, as: UTF8.self),
                     err: String(decoding: err.value, as: UTF8.self), timedOut: timedOut.value)
}

/// 运行并取 stdout（只读探测用）。
func capture(_ launch: String, _ args: [String]) -> (Int32, String) {
    let result = run(launch, args)
    return (result.code, result.out)
}

func tail(_ text: String, lines: Int) -> String {
    let all = text.split(separator: "\n", omittingEmptySubsequences: false)
    return all.suffix(lines).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 用 argv 替换本进程（doctor、versions 的非 JSON 输出原样交给引擎）。
func replace(with program: String, _ args: [String]) -> Never {
    let argv = ([program] + args).map { strdup($0) } + [nil]
    execv(program, argv)
    die("unrevoke: 无法执行 \(program)：\(String(cString: strerror(errno)))", 126)
}

// MARK: - 输出与参数

func jsonText(_ object: Any) -> String {
    let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: options) else {
        return #"{"ok" : false, "error" : "json_encoding"}"#
    }
    return String(decoding: data, as: UTF8.self)
}

func emit(_ object: [String: Any]) { print(jsonText(object)) }

func iso(_ date: Date?) -> Any {
    guard let date else { return NSNull() }
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = .current
    return formatter.string(from: date)
}

func usageError(_ message: String, json: Bool, help: String) -> Never {
    if json {
        emit(["ok": false, "error": "usage", "message": message, "exit_code": Int(Code.usage)])
    } else {
        warn("unrevoke: " + message + "\n\n" + help)
    }
    exit(Code.usage)
}

struct Parsed {
    var flags: Set<String> = []
    var values: [String: String] = [:]
    var positionals: [String] = []
    var json: Bool { flags.contains("--json") }
}

/// 只认列出的开关（flags）与带值选项（options：写法 → 规范名），`--` 之后都算位置参数；其余一律按
/// 用法错误退出 2。以前未知参数会被悄悄忽略，Agent 会以为拼错的开关已经生效。
func parse(_ args: [String], flags known: Set<String>, options: [String: String] = [:],
           positionals limit: Int = 0, help: String) -> Parsed {
    let json = args.contains("--json")
    var parsed = Parsed()
    var index = 0
    var onlyPositionals = false
    while index < args.count {
        let arg = args[index]
        index += 1
        if onlyPositionals || !arg.hasPrefix("-") || arg == "-" {
            parsed.positionals.append(arg)
            continue
        }
        if arg == "--" { onlyPositionals = true; continue }
        if arg == "-h" || arg == "--help" { print(help); exit(Code.ok) }
        if known.contains(arg) { parsed.flags.insert(arg); continue }
        var name = arg
        var inline: String?
        if arg.hasPrefix("--"), let equals = arg.firstIndex(of: "=") {
            name = String(arg[..<equals])
            inline = String(arg[arg.index(after: equals)...])
        }
        guard let canonical = options[name] else { usageError("未知参数 \(arg)", json: json, help: help) }
        // 取值不能空，也不能是下一个开关：`patch -a --json` 以前把 "--json" 当成了路径（以 64 退出、不出 JSON）。
        // 真要以 - 开头的取值写成 --app=<值>。
        let value = inline ?? (index < args.count ? args[index] : nil)
        guard let value, !value.isEmpty, inline != nil || !value.hasPrefix("-") || value == "-" else {
            usageError("\(name) 缺少取值", json: json, help: help)
        }
        if inline == nil { index += 1 }
        parsed.values[canonical] = value
    }
    if parsed.positionals.count > limit {
        let extra = parsed.positionals.dropFirst(limit).joined(separator: " ")
        usageError("多余的参数：\(extra)", json: json, help: help)
    }
    return parsed
}

/// 子命令词可以跟在 --json / --dry-run 之后（`settings --json set …`、`config --json refresh`、
/// `unrevoke --json doctor`）：跳过开头这两个开关找第一个词，找到就把它从参数里拿出、其余参数保持原顺序；
/// 先碰到别的开关（-a、--help、--）就不找，交给各命令自己的 parse。
let hoistable: Set<String> = ["--json", "--dry-run"]

func subcommand(_ args: [String]) -> (word: String, rest: [String])? {
    for (index, arg) in args.enumerated() {
        if hoistable.contains(arg) { continue }
        guard !arg.hasPrefix("-") else { return nil }
        var rest = args
        rest.remove(at: index)
        return (arg, rest)
    }
    return nil
}

func canonical(_ path: String) -> String {
    let expanded = (path as NSString).expandingTildeInPath
    let absolute = expanded.hasPrefix("/") ? expanded : fm.currentDirectoryPath + "/" + expanded
    let standardized = (absolute as NSString).standardizingPath
    guard let real = realpath(standardized, nil) else { return standardized }
    defer { free(real) }
    return String(cString: real)
}

// MARK: - 与界面共用的偏好、目标与补丁库

let guiDomain = "io.github.zengtianli.unrevoke"
/// 测试用沙盒偏好域；生产不设，读写的就是界面那一份。
let prefsDomain = nonEmpty(env["UNREVOKE_DEFAULTS_DOMAIN"]) ?? guiDomain
let wechatBundleID = "com.tencent.xinWeChat"
let defaultWeChatPath = "/Applications/WeChat.app"
let remoteConfigURL = "https://raw.githubusercontent.com/zengtianli/WeChatTweak/refs/heads/master/config.json"
/// 补丁库缓存目录（与 GUI Engine.supportDirectory 同为 Application Support/Unrevoke）；测试用 UNREVOKE_SUPPORT_DIR 换到沙盒。
let supportDir = nonEmpty(env["UNREVOKE_SUPPORT_DIR"]) ?? home + "/Library/Application Support/Unrevoke"
let cachedConfig = supportDir + "/config.json"
let bundledConfig = resources + "/config.json"
/// 界面主程序的进程名（Contents/MacOS/Unrevoke）；测试用 UNREVOKE_GUI_PROCESS 换成替身进程名。
let guiProcessName = nonEmpty(env["UNREVOKE_GUI_PROCESS"]) ?? "Unrevoke"

/// 与 AppModel.Keys、Engine.weChatPath 同名。
enum Key {
    static let variant = "variant"
    static let autoRepatch = "autoRepatch"
    static let everProtected = "everProtected"
    static let lastBuild = "lastBuild"
    static let weChatPath = "weChatPath"
}

/// PatchVariant 的 rawValue；keeptip 是界面缺省（引擎自己的缺省是 silent，所以调用引擎时总是显式传）。
let variants = ["keeptip", "silent"]

/// 只读已存的偏好（同 `defaults read`），不混入命令行参数域。
func savedPrefs() -> [String: Any] {
    UserDefaults.standard.persistentDomain(forName: prefsDomain) ?? [:]
}

var suite: UserDefaults?
func setPref(_ value: Any?, _ key: String) {
    if suite == nil { suite = UserDefaults(suiteName: prefsDomain) }
    guard let defaults = suite else { die("unrevoke: 写不了偏好域 \(prefsDomain)", Code.failed) }
    if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    defaults.synchronize()
}

/// 界面管理的那份微信：偏好 weChatPath（界面的测试接缝），否则 /Applications/WeChat.app。
func guiTarget() -> String { savedPrefs()[Key.weChatPath] as? String ?? defaultWeChatPath }

func guiRunning() -> Bool { run("/usr/bin/pgrep", ["-x", guiProcessName]).code == 0 }

struct ConfigFile {
    let path: String
    let exists: Bool
    let parses: Bool
    let entries: [[String: Any]]?
    let modified: Date?
}

func inspectConfig(_ path: String) -> ConfigFile {
    guard let data = fm.contents(atPath: path) else {
        return ConfigFile(path: path, exists: fm.fileExists(atPath: path), parses: false, entries: nil, modified: nil)
    }
    let object = try? JSONSerialization.jsonObject(with: data)
    let modified = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    return ConfigFile(path: path, exists: true, parses: object != nil, entries: object as? [[String: Any]],
                      modified: modified)
}

/// 与 GUI Engine.activeConfigURL 相同：缓存存在且能解析成 JSON 就用缓存，否则用随包的那份。
func activeConfig() -> (source: String, file: ConfigFile)? {
    let cache = inspectConfig(cachedConfig)
    if cache.parses { return ("cache", cache) }
    let bundled = inspectConfig(bundledConfig)
    return bundled.exists ? ("bundled", bundled) : nil
}

func configArgs(_ args: [String]) -> [String] {
    if args.contains(where: { $0 == "-c" || $0 == "--config" || $0.hasPrefix("--config=") }) { return [] }
    guard let active = activeConfig() else { return [] }
    return ["-c", active.file.path]
}

// MARK: - 引擎（与 GUI 同一份）

func engineEnvironment() -> [String: String] {
    var copy = env
    copy["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
    return copy
}

func requireEngine(json: Bool) {
    guard !isExecutable(engine) else { return }
    let message = "包内缺少引擎 wechattweak，请重新安装 WeChatUnrevoke"
    if json { emit(["ok": false, "error": "engine_missing", "message": message, "exit_code": Int(Code.unavailable)]) }
    die("unrevoke: " + message, Code.unavailable)
}

/// 引擎 `doctor --json`（GUI 解码的同一份契约）；判决只在引擎里算。
func doctorStatus(_ app: String) -> (status: [String: Any]?, code: Int32, error: String) {
    let result = run(engine, ["doctor", "-a", app, "--json"] + configArgs([]), timeout: 60,
                     environment: engineEnvironment())
    if result.timedOut { return (nil, Code.failed, "引擎体检 60 秒没跑完") }
    guard result.code == 0 else {
        return (nil, result.code, result.combined.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    guard let object = try? JSONSerialization.jsonObject(with: Data(result.out.utf8)) as? [String: Any],
          object["overall"] is String else {
        return (nil, Code.failed, "读不懂引擎输出：" + String(result.out.prefix(300)))
    }
    return (object, Code.ok, "")
}

let targetOptions = ["-a": "--app", "--app": "--app", "-c": "--config", "--config": "--config"]

/// doctor / versions 的目标：先核存在，再读 Info.plist 的包名。引擎对任何 .app 都照判（别的 App 多半判成
/// brokenBundle），那个判决对 Agent 是误导，所以包名存在且不以 com.tencent.xinWeChat 开头时以 65 拒绝；
/// 主微信与双开副本（com.tencent.xinWeChat2 等）照常体检，读不到包名（坏包）也照常交给引擎诊断。
func readTarget(_ given: String?, command: String, json: Bool) -> (path: String, bundleID: String?) {
    let app = canonical(given ?? guiTarget())
    func refuse(_ code: Int32, _ error: String, _ message: String, _ extra: [String: Any] = [:]) -> Never {
        if json {
            emit(["ok": false, "error": error, "app_path": app, "message": message, "exit_code": Int(code)]
                .merging(extra) { $1 })
        } else {
            warn("unrevoke \(command)：" + message)
        }
        exit(code)
    }
    guard fm.fileExists(atPath: app) else { refuse(Code.noApp, "no_app", "找不到 \(app)") }
    let bundleID = NSDictionary(contentsOfFile: app + "/Contents/Info.plist")?["CFBundleIdentifier"] as? String
    if let bundleID, !bundleID.hasPrefix(wechatBundleID) {
        refuse(Code.refused, "not_wechat",
               "\(app) 的包名是 \(bundleID)，不是微信（\(wechatBundleID)*）：引擎会照判，但结论没有意义",
               ["bundle_id": bundleID])
    }
    return (app, bundleID)
}

func engineConfig(_ parsed: Parsed) -> [String] {
    parsed.values["--config"].map { ["-c", $0] } ?? configArgs([])
}

let doctorHelp = """
unrevoke doctor — 体检微信（只读，= 界面的状态卡、详情与「重新检查」）

用法：unrevoke doctor [-a <WeChat.app>] [-c <config.json>] [--json]

  -a, --app <路径>      目标微信；缺省与界面相同（偏好 weChatPath，否则 /Applications/WeChat.app）
  -c, --config <文件>   换一份补丁库（本地路径或 URL）；缺省与界面相同（联网缓存能解析就用它，否则随包）
  --json               输出引擎的体检对象（overall 是唯一判决），另加 ok、bundle_id、is_main_wechat
只体检包名以 com.tencent.xinWeChat 开头的包（主微信与双开副本），别的 App 以 65 拒绝；路径不存在以 64 退出。
不加 --json 时原样输出引擎的文字报告。
"""

/// doctor：不写 -a 时与界面看同一份微信。--json 时在引擎的对象上加 ok、bundle_id、is_main_wechat；
/// 引擎失败给 {"ok": false} 并沿用它的退出码。
func doctorCommand(_ args: [String]) -> Never {
    let parsed = parse(args, flags: ["--json"], options: targetOptions, help: doctorHelp)
    let json = parsed.json
    requireEngine(json: json)
    let target = readTarget(parsed.values["--app"], command: "doctor", json: json)
    let engineArgs = ["doctor"] + (json ? ["--json"] : []) + ["-a", target.path] + engineConfig(parsed)
    guard json else { replace(with: engine, engineArgs) }
    let result = run(engine, engineArgs, timeout: 60, environment: engineEnvironment())
    if result.code == 0, !result.timedOut,
       var object = try? JSONSerialization.jsonObject(with: Data(result.out.utf8)) as? [String: Any],
       object["overall"] is String {
        object["ok"] = true
        object["bundle_id"] = target.bundleID ?? NSNull()
        object["is_main_wechat"] = target.bundleID == wechatBundleID
        emit(object)
        exit(Code.ok)
    }
    let code = result.timedOut || result.code == 0 ? Code.failed : result.code
    emit(["ok": false, "error": result.timedOut ? "timeout" : "engine", "app_path": target.path,
          "message": result.combined.trimmingCharacters(in: .whitespacesAndNewlines), "exit_code": Int(code)])
    exit(code)
}

let versionsHelp = """
unrevoke versions — 微信当前版本与补丁库支持的版本

用法：unrevoke versions [-a <WeChat.app>] [-c <config.json>] [--json]

  -a, --app <路径>      目标微信；缺省与界面相同
  -c, --config <文件>   换一份补丁库；缺省与界面相同（联网缓存能解析就用它，否则随包）
  --json               输出 {ok, app_path, bundle_id, current_build, known, supported_builds, supported_count, config}
不加 --json 时原样交给引擎输出文字。路径不存在以 64、不是微信包以 65 退出（同 doctor）。
"""

func versionsCommand(_ args: [String]) -> Never {
    let parsed = parse(args, flags: ["--json"], options: targetOptions, help: versionsHelp)
    let target = readTarget(parsed.values["--app"], command: "versions", json: parsed.json)
    let app = target.path
    guard parsed.json else {
        requireEngine(json: false)
        replace(with: engine, ["versions", "-a", app] + engineConfig(parsed))
    }
    let build = NSDictionary(contentsOfFile: app + "/Contents/Info.plist")?["CFBundleVersion"] as? String
    let source: String
    let file: ConfigFile
    if let custom = parsed.values["--config"] {
        source = "flag"
        file = inspectConfig(canonical(custom))
    } else if let active = activeConfig() {
        source = active.source
        file = active.file
    } else {
        emit(["ok": false, "error": "no_config", "message": "没有可用的补丁库", "exit_code": Int(Code.unavailable)])
        exit(Code.unavailable)
    }
    guard let entries = file.entries else {
        emit(["ok": false, "error": "invalid_config", "message": "\(file.path) 不是补丁库（--json 只读本地文件）",
              "exit_code": Int(Code.failed)])
        exit(Code.failed)
    }
    let builds = entries.compactMap { $0["version"] as? String }
    emit(["ok": true, "app_path": app, "bundle_id": target.bundleID ?? NSNull(), "current_build": build ?? NSNull(),
          "known": build.map { builds.contains($0) } ?? false,
          "supported_builds": builds, "supported_count": builds.count,
          "config": ["source": source, "path": file.path]])
    exit(Code.ok)
}

// MARK: - settings（界面的偏好）

let settingsHelp = """
unrevoke settings — 界面偏好（与界面同一个偏好域、同键名、同缺省值）

用法：
  unrevoke settings [--json]                               只读：防撤回方式、自动重打、曾经保护过、上次看到的版本、目标微信
  unrevoke settings set variant <keeptip|silent> [--json]  =「防撤回方式」选择器
  unrevoke settings set auto-repatch <on|off> [--json]     =「微信更新后自动打回补丁」开关

界面开着时，它启动时读到的值留在内存里：命令行写的新值要重开界面才生效，在界面里再拨这个开关会覆盖它。
「开机自动运行」用 unrevoke login，由同包主程序登记（SMAppService）。
"""

func settingsSnapshot() -> [String: Any] {
    let saved = savedPrefs()
    let savedVariant = (saved[Key.variant] as? String).flatMap { variants.contains($0) ? $0 : nil }
    let savedAuto = saved[Key.autoRepatch] as? Bool
    let path = saved[Key.weChatPath] as? String
    return [
        "ok": true, "domain": prefsDomain,
        "variant": savedVariant ?? "keeptip", "variant_saved": savedVariant != nil,
        "auto_repatch": savedAuto ?? true, "auto_repatch_saved": savedAuto != nil,
        "ever_protected": saved[Key.everProtected] as? Bool ?? false,
        "last_build": saved[Key.lastBuild] as? String ?? NSNull(),
        "wechat_path": path ?? defaultWeChatPath, "wechat_path_overridden": path != nil,
        "gui_running": guiRunning(),
    ]
}

func settingsCommand(_ args: [String]) -> Never {
    if let sub = subcommand(args), sub.word == "set" { settingsSet(sub.rest) }
    let parsed = parse(args, flags: ["--json"], help: settingsHelp)
    let snapshot = settingsSnapshot()
    if parsed.json { emit(snapshot); exit(Code.ok) }
    func mark(_ saved: Any?) -> String { (saved as? Bool) == true ? "" : "（缺省）" }
    print("防撤回方式 variant          \(snapshot["variant"]!)\(mark(snapshot["variant_saved"]))")
    print("自动重打 autoRepatch         \((snapshot["auto_repatch"] as? Bool) == true ? "开" : "关")\(mark(snapshot["auto_repatch_saved"]))")
    print("曾经保护过 everProtected      \((snapshot["ever_protected"] as? Bool) == true ? "是" : "否")")
    print("上次看到的版本 lastBuild      \(snapshot["last_build"] as? String ?? "—")")
    print("目标微信 weChatPath          \(snapshot["wechat_path"]!)\((snapshot["wechat_path_overridden"] as? Bool) == true ? "（偏好改过）" : "（缺省）")")
    print("界面进程                     \((snapshot["gui_running"] as? Bool) == true ? "运行中" : "未运行")")
    print("开机自动运行                 unrevoke login status 读取；login on|off --yes 修改")
    exit(Code.ok)
}

func settingsSet(_ args: [String]) -> Never {
    let parsed = parse(args, flags: ["--json"], positionals: 2, help: settingsHelp)
    let json = parsed.json
    guard parsed.positionals.count == 2 else {
        usageError("用法：settings set variant <keeptip|silent> 或 settings set auto-repatch <on|off>",
                   json: json, help: settingsHelp)
    }
    let key = parsed.positionals[0], raw = parsed.positionals[1]
    let before = settingsSnapshot()
    var result: [String: Any] = ["domain": prefsDomain, "key": key]
    let previous: Any, value: Any
    let changed: Bool
    switch key {
    case "variant":
        guard variants.contains(raw) else { usageError("variant 只能是 keeptip 或 silent", json: json, help: settingsHelp) }
        let old = before["variant"] as? String ?? "keeptip"
        previous = old; value = raw; changed = old != raw
        if changed { setPref(raw, Key.variant) }
    case "auto-repatch":
        guard let flag = ["on": true, "off": false][raw] else {
            usageError("auto-repatch 只能是 on 或 off", json: json, help: settingsHelp)
        }
        let old = before["auto_repatch"] as? Bool ?? true
        previous = old; value = flag; changed = old != flag
        if changed { setPref(flag, Key.autoRepatch) }
    default:
        usageError("可设置的只有 variant 与 auto-repatch", json: json, help: settingsHelp)
    }
    let after = settingsSnapshot()
    let readBack: Any? = key == "variant" ? after["variant"] : after["auto_repatch"]
    let verified = (readBack as? NSObject)?.isEqual(value) ?? false
    let gui = after["gui_running"] as? Bool ?? false
    result["ok"] = verified
    result["previous"] = previous
    result["value"] = value
    result["changed"] = changed
    result["gui_running"] = gui
    result["note"] = gui && changed
        ? "界面开着：重开界面后才用新值；在界面里再拨这个开关会覆盖命令行写的值" : NSNull()
    if json { emit(result) } else if verified {
        print("\(key)：\(previous) → \(value)\(changed ? "（已写入 \(prefsDomain)）" : "（未变）")")
        if let note = result["note"] as? String { print(note) }
    } else {
        warn("unrevoke settings set：写入后读回不一致（\(key)=\(readBack ?? "nil")）")
    }
    exit(verified ? Code.ok : Code.failed)
}

// MARK: - config（补丁库）

let configHelp = """
unrevoke config — 正在用的补丁库（与界面同一份）

用法：
  unrevoke config [--json]                     只读：用的是联网缓存还是随包、路径、条目数、修改时间
  unrevoke config refresh [--dry-run] [--json] 联网拉最新补丁库写进缓存（= 界面每次启动做的那一步）

refresh 与界面同一套 fail-closed 规则：HTTP 200、非空 JSON 数组、条目数不少于现有的才写（原子写入）；
条目数变多时再体检一次界面那份微信，报告新版本是否已被认识。网络或内容不合格时不动缓存，以 1 退出。
"""

func describe(_ file: ConfigFile) -> [String: Any] {
    ["path": file.path, "exists": file.exists, "valid": file.parses,
     "entries": file.entries.map { $0.count as Any } ?? NSNull(), "modified": iso(file.modified)]
}

func configCommand(_ args: [String]) -> Never {
    if let sub = subcommand(args), sub.word == "refresh" { configRefresh(sub.rest) }
    let parsed = parse(args, flags: ["--json"], help: configHelp)
    let active = activeConfig()
    let object: [String: Any] = [
        "ok": active != nil, "source": active?.source ?? NSNull(), "path": active?.file.path ?? NSNull(),
        "entries": active?.file.entries.map { $0.count as Any } ?? NSNull(),
        "modified": iso(active?.file.modified),
        "cache": describe(inspectConfig(cachedConfig)), "bundled": describe(inspectConfig(bundledConfig)),
        "remote_url": remoteConfigURL,
    ]
    if parsed.json { emit(object) } else if let active {
        let label = active.source == "cache" ? "联网缓存" : "随包"
        print("补丁库：\(label) \(active.file.path)")
        print("条目：\(active.file.entries?.count ?? 0)；修改时间：\(iso(active.file.modified))")
        print("远端：\(remoteConfigURL)（unrevoke config refresh 拉新）")
    } else {
        warn("unrevoke config：没有可用的补丁库（缓存与随包都没有）")
    }
    exit(active != nil ? Code.ok : Code.unavailable)
}

final class Fetched: @unchecked Sendable {
    var data: Data?
    var response: URLResponse?
    var error: Error?
}

func fetch(_ url: URL) -> Fetched {
    // 与 GUI Engine.refreshConfig 相同：15 秒超时、绕过本地缓存。
    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let box = Fetched()
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, response, error in
        box.data = data
        box.response = response
        box.error = error
        done.signal()
    }.resume()
    done.wait()
    return box
}

func configRefresh(_ args: [String]) -> Never {
    let parsed = parse(args, flags: ["--json", "--dry-run"], help: configHelp)
    let json = parsed.json, dryRun = parsed.flags.contains("--dry-run")
    // 测试用 UNREVOKE_CONFIG_URL 指向本地夹具服务；生产不设。
    let urlText = nonEmpty(env["UNREVOKE_CONFIG_URL"]) ?? remoteConfigURL
    var object: [String: Any] = ["action": "config refresh", "url": urlText, "path": cachedConfig, "dry_run": dryRun]
    func finish(_ ok: Bool, _ result: String, _ message: String, _ code: Int32) -> Never {
        object["ok"] = ok
        object["result"] = result
        object["message"] = message
        object["exit_code"] = Int(code)
        if json { emit(object) } else if ok { print(message) } else { warn("unrevoke config refresh：" + message) }
        exit(code)
    }
    guard let url = URL(string: urlText) else { finish(false, "failed", "地址无效：\(urlText)", Code.failed) }
    let currentCount = activeConfig()?.file.entries?.count ?? 0
    object["previous_entries"] = currentCount
    let fetched = fetch(url)
    if let error = fetched.error { finish(false, "failed", "联网失败：\(error.localizedDescription)", Code.failed) }
    let status = (fetched.response as? HTTPURLResponse)?.statusCode
    object["http_status"] = status ?? NSNull()
    guard status == 200, let data = fetched.data else {
        finish(false, "rejected", "HTTP \(status.map(String.init) ?? "?")，缓存未动", Code.failed)
    }
    guard let incoming = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !incoming.isEmpty else {
        finish(false, "rejected", "响应不是非空的补丁库 JSON 数组，缓存未动", Code.failed)
    }
    object["incoming_entries"] = incoming.count
    guard incoming.count >= currentCount else {
        finish(false, "rejected", "远端 \(incoming.count) 条少于现有 \(currentCount) 条（多半是半截响应），缓存未动", Code.failed)
    }
    let unchanged = fm.contents(atPath: cachedConfig) == data
    let grew = incoming.count > currentCount
    if unchanged { finish(true, "unchanged", "补丁库已是最新（\(incoming.count) 条）", Code.ok) }
    if dryRun {
        finish(true, grew ? "would_update" : "would_refresh",
               "会写入 \(incoming.count) 条（现有 \(currentCount) 条；--dry-run，未写）", Code.ok)
    }
    do {
        try fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: cachedConfig), options: .atomic)
    } catch {
        finish(false, "failed", "写缓存失败：\(error.localizedDescription)", Code.failed)
    }
    // 界面在补丁库变多后会提示并再体检一次；这里同样报告界面那份微信现在是否被认识。
    let target = guiTarget()
    if grew, isExecutable(engine), fm.fileExists(atPath: target) {
        let check = doctorStatus(target)
        if let status = check.status {
            object["doctor"] = ["app_path": target, "overall": status["overall"] ?? NSNull(),
                                "build": status["build"] ?? NSNull(), "config_known": status["config_known"] ?? NSNull()]
        }
    }
    finish(true, grew ? "updated" : "refreshed",
           grew ? "补丁库已更新：\(currentCount) → \(incoming.count) 条" : "补丁库已刷新（\(incoming.count) 条）", Code.ok)
}

// MARK: - patch / restore（界面的两个写按钮）

let patchHelp = """
unrevoke patch — 开启防撤回 / 补齐（= 界面的「开启防撤回」「补齐」按钮，同一个引擎、同一套参数）

用法：unrevoke patch [-a <WeChat.app>] [--variant keeptip|silent] [--sudo] [--quit-wechat] [--dry-run] [--json]

  -a, --app <路径>     目标微信；缺省与界面相同（偏好 weChatPath，否则 /Applications/WeChat.app）
  --variant <方式>     keeptip（保留撤回提示）或 silent；缺省取界面里选的方式（未选过为 keeptip）
  --quit-wechat       显式确认退出所选微信，等体检确认退出后继续；成功后后台重新打开同一份微信
  --sudo              包需要管理员（writable=false）时经 sudo -n 用已有的免密规则；不加则以 77 退出
  --dry-run           只体检并给出将要执行的引擎命令，不写
  --json              输出 {ok, result, reason, message, before, after, command, via, variant, engine_output}

前提与界面一致：判决为 unprotected 或 partial 才写；protected / antiRevokeOnly 视为已完成（result
already_protected，退出 0）；brokenBundle、mixed、unsupportedBuild 拒绝（65）。微信正在运行时拒绝（75）——
不带 --quit-wechat 不会退出微信；带参数只请求所选 App 正常退出，不强退，--dry-run 不退出。
界面开着且目标就是界面那份微信时也拒绝（75），避免与界面的自动重打同时写一个包。
只处理 CFBundleIdentifier 为 com.tencent.xinWeChat 的包。写完总会重新体检：判决为 protected 或
antiRevokeOnly 才以 0 退出。重签要几十秒，命令会等到结束；过程中的状态随时可用 unrevoke doctor --json 查。
"""

let restoreHelp = """
unrevoke restore — 还原微信（= 界面的「还原微信」按钮，--yes 代替确认对话框）

用法：unrevoke restore --yes [-a <WeChat.app>] [--sudo] [--quit-wechat] [--dry-run] [--json]

  --yes               确认还原：补丁点写回原始字节并重签，防撤回失效、微信自动更新恢复；不加则以 2 退出
  --quit-wechat       另行确认退出所选微信并在成功后后台重开；不带时微信运行仍以 75 拒绝
  -a, --app <路径>     目标微信；缺省与界面相同
  --sudo              包需要管理员（writable=false）时经 sudo -n 用已有的免密规则；不加则以 77 退出
  --dry-run           只体检并给出将要执行的引擎命令，不写（不需要 --yes）
  --json              输出 {ok, result, reason, message, before, after, command, via, engine_output}

前提与界面一致：判决为 protected、antiRevokeOnly 或 partial 才写；unprotected 视为已完成（退出 0）；
其余拒绝（65）。微信运行且未带 --quit-wechat、或界面正在运行时拒绝（75）。目标是界面那份微信时，先把「曾经保护过」置否（界面的
自动重打因此不会跟还原抢着写），没还原成则放回原值。写完重新体检，判决为 unprotected 才以 0 退出。
"""

let patchAllowed: Set<String> = ["unprotected", "partial"]                   // ContentView：开启防撤回 / 补齐
let patchDone: Set<String> = ["protected", "antiRevokeOnly"]                  // 已生效：界面只给「重新检查」
let restoreAllowed: Set<String> = ["protected", "antiRevokeOnly", "partial"]  // ContentView 页脚「还原微信」
let restoreDone: Set<String> = ["unprotected"]

/// 与 GUI Engine.writeFailure 相同的「被拒绝写入」判断（错误码优先，措辞兜底）。
func permissionDenied(_ output: String) -> Bool {
    let text = output.lowercased().replacingOccurrences(of: "’", with: "'")
    if text.range(of: #"nscocoaerrordomain\s+code\s*=\s*(?:513|257)\b"#, options: .regularExpression) != nil {
        return true
    }
    if ["permission denied", "operation not permitted",
        "don't have permission", "do not have permission"].contains(where: { text.contains($0) }) {
        return true
    }
    return text.range(of: #"(?:没有|沒有)[^\n]*(?:权限|權限)"#, options: .regularExpression) != nil
}

func verdictAdvice(_ overall: String, action: String) -> String {
    switch overall {
    case "brokenBundle":
        return "微信的签名权限已丢失（brokenBundle），界面此时只给「去下载微信」：从 mac.weixin.qq.com 重装后再来"
    case "mixed":
        return "补丁点的字节既不是原始的也不是本工具写的（mixed），多半被别的工具改过；重装微信后再来"
    case "unsupportedBuild":
        return "补丁库还没收录这个微信版本（unsupportedBuild）：先 unrevoke config refresh，再 unrevoke doctor 看是否已支持"
    default:
        return "当前判决 \(overall) 不允许 \(action)（界面此时也不给这个按钮）"
    }
}

var lockDescriptor: Int32 = -1

/// 同一时间只允许一个命令行写入（flock，进程退出自动释放）。界面的「忙」只在它自己进程里，另由 gui_running 挡住。
func lockWrites() -> String? {
    do {
        try fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
    } catch {
        return "建不了 \(supportDir)：\(error.localizedDescription)"
    }
    let fd = open(supportDir + "/.cli-write.lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
    guard fd >= 0 else { return "打不开写入锁：\(String(cString: strerror(errno)))" }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
        close(fd)
        return "busy"
    }
    lockDescriptor = fd
    return nil
}

func writeCommand(_ action: String, _ args: [String]) -> Never {
    let isPatch = action == "patch"
    let help = isPatch ? patchHelp : restoreHelp
    var flags: Set<String> = ["--json", "--dry-run", "--sudo", "--quit-wechat"]
    var options = ["-a": "--app", "--app": "--app"]
    if isPatch { options["--variant"] = "--variant" } else { flags.insert("--yes") }
    let parsed = parse(args, flags: flags, options: options, help: help)
    let json = parsed.json, dryRun = parsed.flags.contains("--dry-run")
    var report: [String: Any] = ["action": action, "dry_run": dryRun]
    var quitTarget: String?

    func finish(_ ok: Bool, _ code: Int32, _ result: String, _ reason: String?, _ message: String) -> Never {
        var ok = ok, code = code, reason = reason, message = message
        if ok, let target = quitTarget {
            let reopened = WeChatProcessControl.live.reopen(target)
            report["reopened"] = reopened
            if !reopened {
                ok = false; code = Code.failed; reason = "reopen_failed"
                message += "；所选微信未重新打开，请核对 after 中的实际写入结果"
            }
        }
        report["ok"] = ok
        report["exit_code"] = Int(code)
        report["result"] = result
        report["reason"] = reason ?? NSNull()
        report["message"] = message
        if json {
            emit(report)
        } else {
            if let output = report["engine_output"] as? String, !output.isEmpty { warn(output) }
            let latest = (report["after"] as? [String: Any]) ?? (report["before"] as? [String: Any])
            let state = latest.map { "（\($0["app_path"] ?? "?")：\($0["overall"] ?? "?")，build \($0["build"] ?? "?")）" } ?? ""
            if ok { print(message + state) } else { warn("unrevoke \(action)：" + message + state) }
        }
        exit(code)
    }

    if !isPatch && !dryRun && !parsed.flags.contains("--yes") {
        finish(false, Code.usage, "refused", "confirmation_required",
               "还原会把补丁点写回原始字节并重签，防撤回失效、微信自动更新恢复。确认请加 --yes（界面里是确认对话框），或先用 --dry-run 看计划")
    }
    let variantFlag = parsed.values["--variant"]
    if let variantFlag, !variants.contains(variantFlag) {
        usageError("--variant 只能是 keeptip 或 silent", json: json, help: help)
    }
    let guiPath = canonical(guiTarget())
    let app = canonical(parsed.values["--app"] ?? guiTarget())
    let isGuiTarget = app == guiPath
    report["app_path"] = app
    report["gui_target"] = isGuiTarget
    guard fm.fileExists(atPath: app) else { finish(false, Code.noApp, "refused", "no_app", "找不到 \(app)") }
    let bundleID = NSDictionary(contentsOfFile: app + "/Contents/Info.plist")?["CFBundleIdentifier"] as? String
    report["bundle_id"] = bundleID ?? NSNull()
    guard bundleID == wechatBundleID else {
        finish(false, Code.refused, "refused", "not_main_wechat",
               "只处理主微信包（CFBundleIdentifier 为 \(wechatBundleID)，界面管理的也是它）。双开副本 WeChat2 打补丁后还要用 WeChat3 的权限集重签，按 ~/Apps/wechat/README.md 的步骤做，这里不代做")
    }
    guard isExecutable(engine) else {
        finish(false, Code.unavailable, "failed", "engine_missing", "包内缺少引擎 wechattweak，请重新安装 WeChatUnrevoke")
    }

    var variant = "keeptip"
    if isPatch {
        let saved = (savedPrefs()[Key.variant] as? String).flatMap { variants.contains($0) ? $0 : nil }
        variant = variantFlag ?? saved ?? "keeptip"
        report["variant"] = variant
        report["variant_source"] = variantFlag != nil ? "flag" : (saved != nil ? "saved" : "default")
    }

    // 真写入先拿锁、再体检：把门的判决必须是持锁时读到的（同界面 AppModel.write 先置 isBusy 再体检）。
    // 以前先体检后拿锁，两条并发的 patch/restore 会都过门，后一条拿着过期判决去写。--dry-run 不写，不拿锁。
    if !dryRun, let problem = lockWrites() {
        if problem == "busy" {
            finish(false, Code.busy, "refused", "busy", "另一个 unrevoke patch/restore 正在进行，等它结束再试")
        }
        finish(false, Code.failed, "failed", "lock", problem)
    }

    // 前提由「这一次」体检决定（与界面 AppModel 铁律 2 相同），不用缓存。
    let first = doctorStatus(app)
    guard var before = first.status else {
        finish(false, first.code == Code.ok ? Code.failed : first.code, "failed", "doctor_failed", "体检失败：" + first.error)
    }
    report["before"] = before
    let overall = before["overall"] as? String ?? "?"
    if isPatch {
        if patchDone.contains(overall) {
            finish(true, Code.ok, "already_protected", nil, "防撤回已生效（\(overall)），不重复打补丁")
        }
        guard patchAllowed.contains(overall) else {
            finish(false, Code.refused, "refused", "verdict", verdictAdvice(overall, action: action))
        }
    } else {
        if restoreDone.contains(overall) {
            finish(true, Code.ok, "already_stock", nil, "微信已是原样（unprotected），无需还原")
        }
        guard restoreAllowed.contains(overall) else {
            finish(false, Code.refused, "refused", "verdict", verdictAdvice(overall, action: action))
        }
    }
    if before["running"] as? Bool == true && !parsed.flags.contains("--quit-wechat") {
        finish(false, Code.busy, "refused", "wechat_running",
               "微信正在运行。先自行退出，或显式加 --quit-wechat 确认退出所选微信并在成功后重新打开；不带该参数不会代为退出")
    }
    if isGuiTarget && guiRunning() {
        finish(false, Code.busy, "refused", "gui_running",
               "WeChatUnrevoke 界面开着，而目标就是界面管理的那份微信：界面发现补丁不在时会自动重打，和命令行同时写一个包会冲突。先退出界面再重跑，或直接用界面上的按钮")
    }
    var needsAdmin = !(before["writable"] as? Bool ?? false)
    report["needs_admin"] = needsAdmin
    if needsAdmin && !parsed.flags.contains("--sudo") {
        finish(false, Code.permission, "refused", "needs_admin",
               "这个微信包需要管理员权限才能修改（writable=false）。加 --sudo 经 sudo -n 使用 /etc/sudoers.d 里钉住随包引擎摘要的免密规则（不弹密码、不新增规则）；没有免密规则时请用界面，它会弹系统授权框")
    }

    if parsed.flags.contains("--quit-wechat") {
        report["quit_wechat"] = true
        if before["running"] as? Bool == true {
            if dryRun {
                report["quit_requested"] = false
            } else {
                report["quit_requested"] = true
                var freshStatus: [String: Any]?
                let stopped = WeChatProcessControl.live.quitAndWait(target: app) {
                    let readback = doctorStatus(app)
                    freshStatus = readback.status
                    return readback.status?["running"] as? Bool
                }
                guard stopped, let fresh = freshStatus else {
                    finish(false, Code.busy, "refused", "wechat_still_running",
                           "所选微信未完全退出或退出后体检失败；没有写入，也不会强退进程")
                }
                quitTarget = app
                before = fresh
                report["before_write"] = fresh
                let freshOverall = fresh["overall"] as? String ?? "?"
                if isPatch ? patchDone.contains(freshOverall) : restoreDone.contains(freshOverall) {
                    finish(true, Code.ok, isPatch ? "already_protected" : "already_stock", nil,
                           "退出后体检已是目标状态，无需写入")
                }
                guard isPatch ? patchAllowed.contains(freshOverall) : restoreAllowed.contains(freshOverall) else {
                    finish(false, Code.refused, "refused", "verdict", verdictAdvice(freshOverall, action: action))
                }
                needsAdmin = !(fresh["writable"] as? Bool ?? false)
                report["needs_admin"] = needsAdmin
                if needsAdmin && !parsed.flags.contains("--sudo") {
                    finish(false, Code.permission, "refused", "needs_admin", "退出后体检需要管理员；没有写入，请核对权限后重试")
                }
            }
        }
    }

    // 与 GUI Engine.patch / Engine.restore 相同的参数（tests/test_dispatcher.py 钉住）。
    let engineArgs = isPatch
        ? ["patch", "-a", app, "--variant", variant, "--auto-locate"] + configArgs([])
        : ["restore", "-a", app] + configArgs([])
    let argv = needsAdmin ? ["/usr/bin/sudo", "-n", engine] + engineArgs : [engine] + engineArgs
    report["via"] = needsAdmin ? "sudo -n" : "direct"
    report["command"] = argv
    if dryRun {
        finish(true, Code.ok, isPatch ? "would_patch" : "would_restore", nil,
               "计划：" + argv.joined(separator: " ") + "（--dry-run，未写入）")
    }

    let savedEver = savedPrefs()[Key.everProtected]
    if !isPatch && isGuiTarget { setPref(false, Key.everProtected) }
    let result = run(argv[0], Array(argv.dropFirst()), timeout: 600, environment: engineEnvironment())
    // 无论成败都重新体检一次：失败也可能已经写了一半（同界面 AppModel.write）。
    let second = doctorStatus(app)
    report["after"] = second.status ?? NSNull()
    report["engine_exit_code"] = Int(result.code)
    report["engine_output"] = tail(result.combined, lines: 60)
    let afterOverall = second.status?["overall"] as? String ?? ""
    let succeeded = !result.timedOut && result.code == 0
        && (isPatch ? patchDone.contains(afterOverall) : restoreDone.contains(afterOverall))
    if isGuiTarget {
        if let build = second.status?["build"] as? String { setPref(build, Key.lastBuild) }
        if isPatch && succeeded { setPref(true, Key.everProtected) }
        if !isPatch && !succeeded { setPref(savedEver, Key.everProtected) }
    }
    if succeeded {
        finish(true, Code.ok, isPatch ? "patched" : "restored", nil,
               isPatch ? "已开启防撤回（\(variant)）" : "已还原成原样，微信的自动更新也恢复了")
    }
    if result.timedOut {
        finish(false, Code.failed, "failed", "timeout", "引擎 600 秒没跑完，已终止；实际状态见体检")
    }
    let output = result.combined
    if needsAdmin && result.code != 0 && output.contains("sudo:") && output.lowercased().contains("password") {
        finish(false, Code.permission, "failed", "sudo_password_required",
               "sudo -n 需要密码：免密规则不在或引擎摘要变了（见 ~/Apps/unrevoke/CLAUDE.md「刷新 sudo 免密摘要」，需本人以管理员执行）；也可以用界面，它会弹系统授权框")
    }
    if result.code != 0 && permissionDenied(output) {
        finish(false, Code.permission, "failed", "permission_denied",
               "macOS 拒绝修改微信文件：到「系统设置 → 隐私与安全性 → App 管理」允许运行这条命令的终端 App 修改其他 App 后重跑，管理员密码不能代替这项授权；仍失败时检查微信文件的所有者、权限与锁定状态")
    }
    if result.code != 0 && second.status?["running"] as? Bool == true {
        finish(false, Code.busy, "failed", "wechat_running", "微信在写入前又被打开了，引擎拒绝写入；退出微信后重跑")
    }
    if result.code != 0 {
        finish(false, Code.failed, "failed", "engine_failed", "引擎失败（退出码 \(result.code)），实际状态见体检")
    }
    finish(false, Code.failed, "failed", isPatch ? "not_protected_after_write" : "not_restored_after_write",
           "引擎退出 0，但体检判决是 \(afterOverall.isEmpty ? "未知" : afterOverall)")
}

// MARK: - 帮助与分派

func versionInfo() -> (short: String, build: String) {
    let info = NSDictionary(contentsOfFile: contents + "/Info.plist")
    return (info?["CFBundleShortVersionString"] as? String ?? "?", info?["CFBundleVersion"] as? String ?? "?")
}

let usage = """
unrevoke — WeChatUnrevoke 命令行。界面给人用，命令行给 Agent 用：同一个引擎、补丁库与偏好。

只读（不写任何文件；读回当前状态用 doctor）：
  unrevoke doctor [--json] [-a <WeChat.app>]     体检：补丁状态、签名、SIP；缺省目标与界面相同
  unrevoke versions [--json] [-a <WeChat.app>]   当前微信版本与补丁库支持的版本
  unrevoke settings [--json]                      界面偏好：防撤回方式、自动重打、目标微信
  unrevoke config [--json]                        正在用的补丁库（联网缓存或随包）
写入（与界面按钮同一套前提；先用 --dry-run 看计划）：
  unrevoke patch [-a <app>] [--variant keeptip|silent] [--sudo] [--dry-run] [--json]   开启防撤回 / 补齐
  unrevoke restore --yes [-a <app>] [--sudo] [--dry-run] [--json]                     还原微信
  unrevoke settings set variant <keeptip|silent> | auto-repatch <on|off> [--json]
  unrevoke config refresh [--dry-run] [--json]    联网更新补丁库（与界面启动时同一规则）
其他：
  unrevoke version [--json] | --version | --help

--json 输出：成功 {"ok": true, …}；失败 {"ok": false, …, "message": 原因, "exit_code": N}，同时退出码非 0。
失败的短码：用法错误与只读命令在 "error"（usage、no_app、not_wechat、engine、timeout、engine_missing、
no_config、invalid_config）；patch、restore 在 "result"（refused / failed）与 "reason"；config refresh 在 "result"。
  doctor          引擎的体检对象 {overall, build, app_path, config_known, config_targets, running, writable, sip,
                  signature, entitlements_ok, entitlement_key_count, anti_revoke_keeptip, anti_revoke_silent,
                  update_block, update_source, verdict[, sparkle, next_command]} 加 {bundle_id, is_main_wechat}；
                  overall 是唯一判决
  versions        {app_path, bundle_id, current_build, known, supported_builds, supported_count, config: {source, path}}
  settings        {domain, variant, variant_saved, auto_repatch, auto_repatch_saved, ever_protected, last_build,
                  wechat_path, wechat_path_overridden, gui_running}
  settings set    {domain, key, previous, value, changed, gui_running, note}
  config          {source, path, entries, modified, cache: {path, exists, valid, entries, modified}, bundled: {同 cache},
                  remote_url}
  config refresh  {action, url, path, dry_run, result, message, exit_code, previous_entries, http_status,
                  incoming_entries[, doctor]}
  patch / restore {action, dry_run, result, reason, message, exit_code, app_path, gui_target, bundle_id, before, after,
                  needs_admin, via, command, engine_exit_code, engine_output[, variant, variant_source,
                  quit_wechat, quit_requested, before_write, reopened]}
  version         {version, build}

退出码：
  0   成功，或已是目标状态无需操作
  1   失败：引擎失败、写后判决不对、联网或补丁库不合格
  2   用法错误：未知命令或参数、取值不对或缺取值、restore 没带 --yes
  64  -a 路径不存在
  65  当前判决或目标不允许（界面此时也不给这个按钮；patch、restore 只处理主微信包）
  69  包内缺件（引擎或补丁库）
  75  微信或界面正在运行，或另一个写入在进行
  77  需要管理员（没加 --sudo 或免密规则失效），或 macOS 拒绝修改
  不加 --json 的 doctor、versions 把引擎自己的退出码原样交回；126 为包内程序无法执行。

仅在窗口中（真人操作，或只在窗口里有意义）：
  去下载微信                在浏览器打开 mac.weixin.qq.com；下载并重装微信要本人做
  安装教程与使用帮助        在浏览器打开 https://unrevoke.tianli.cyou/
  管理员密码授权框          系统弹窗要真人输入密码；已有免密规则时用 patch、restore 的 --sudo
  通知授权                  打开「微信更新后自动打回补丁」时系统询问是否允许通知，要真人点
  设置…                     打开「设置」窗口（⌘,）；窗口里的当前版本用 unrevoke version 读
界面有、命令暂缺：
  本构建提供以下入口；装机验收以 Chapter 当前登记和固定脚本为准：
  开机自动运行：unrevoke login；退出微信并继续（完成后重新打开微信）：patch/restore --quit-wechat；
  界面上一次写入的引擎日志与错误：unrevoke logs；使用 iCloud 记住配置：unrevoke config sync；
  导出配置：unrevoke config export；导入配置：unrevoke config import；检查更新：unrevoke update check；升级到新版：unrevoke update install。
命令入口：
  unrevoke login [status|on|off] [--json] [--dry-run] [--yes]
  unrevoke logs [--json]
  unrevoke config status [--json]
  unrevoke config export -o <file> [--json]
  unrevoke config import <file> --yes [--json]
  unrevoke config sync on|off --yes [--dry-run] [--json]
  unrevoke update check [--json]
  unrevoke update install --yes [--dry-run] [--json]
  config status/export/import/sync 与 update 由同包共享生命周期层处理；裸 config 与 config refresh 仍操作补丁库。
各命令 --help 看细节。
"""

let versionHelp = """
unrevoke version — 本命令行与所在 WeChatUnrevoke.app 的版本

用法：unrevoke version [--json]      也可写 unrevoke --version 或 -V
  --json   输出 {ok, version, build}
"""

let loginHelp = """
unrevoke login — 与界面同一个开机登录项
用法：unrevoke login [status|on|off] [--json] [--dry-run] [--yes]
status 只读；on/off 要 --yes，由同包主程序登记并回读。
--dry-run 不登记。系统要求批准时只报告，不打开设置或弹窗。
"""

func loginCommand(_ args: [String]) -> Never {
    let parsed = parse(args, flags: ["--json", "--dry-run", "--yes"], positionals: 1, help: loginHelp)
    let verb = parsed.positionals.first ?? "status"
    guard ["status", "on", "off"].contains(verb) else {
        usageError("login 只接受 status、on 或 off", json: parsed.json, help: loginHelp)
    }
    let executable = NSDictionary(contentsOfFile: contents + "/Info.plist")?["CFBundleExecutable"] as? String ?? "Unrevoke"
    let program = contents + "/MacOS/" + executable
    guard isExecutable(program) else { die("包内主程序不存在，无法读取或登记登录项", Code.unavailable) }
    let forwarded = ["--login", verb] + ["--json", "--dry-run", "--yes"].filter(parsed.flags.contains)
    let result = run(program, forwarded, timeout: 30)
    if !result.out.isEmpty { FileHandle.standardOutput.write(Data(result.out.utf8)) }
    if !result.err.isEmpty { FileHandle.standardError.write(Data(result.err.utf8)) }
    exit(result.timedOut ? Code.busy : result.code)
}

let logsHelp = """
unrevoke logs — 界面上一次写入的引擎日志与错误（只读）
用法：unrevoke logs [--json]
只读取本地记录，不启动界面、不查询微信、不导出或同步该记录。
没有记录时成功返回 exists=false；损坏或不可读时非 0 退出。
"""

func logsCommand(_ args: [String]) -> Never {
    let parsed = parse(args, flags: ["--json"], help: logsHelp)
    let url = URL(fileURLWithPath: supportDir).appendingPathComponent("Logs/last-write.json")
    do {
        let record = try WriteHistoryStore(recordURL: url).load()
        if parsed.json {
            let value: Any = try record.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
            emit(["ok": true, "exists": record != nil, "record": value])
        } else if let record {
            print("上次写入：\(record.action) · \(record.completedAt)\n\(record.lastEngineLog)")
            print("错误：\(record.lastWriteError ?? "(none)")")
        } else { print("界面尚未留下写入记录") }
        exit(Code.ok)
    } catch {
        if parsed.json { emit(["ok": false, "error": "history_unreadable", "message": error.localizedDescription]) }
        else { warn(error.localizedDescription) }
        exit(Code.failed)
    }
}

func versionCommand(_ args: [String]) -> Never {
    let parsed = parse(args, flags: ["--json"], help: versionHelp)
    let info = versionInfo()
    if parsed.json {
        emit(["ok": true, "version": info.short, "build": info.build])
    } else {
        print("unrevoke \(info.short) (\(info.build))")
    }
    exit(Code.ok)
}

let arguments = Array(CommandLine.arguments.dropFirst())
// `unrevoke --json doctor` 与 `unrevoke doctor --json` 等价；-h/--version 等开头的照旧按第一个参数分派。
let (command, rest): (String?, [String]) = subcommand(arguments).map { ($0.word, $0.rest) }
    ?? (arguments.first, Array(arguments.dropFirst()))
if let command, UnrevokeLifecycle.handles([command] + rest) {
    exit(UnrevokeLifecycle.run([command] + rest, executableURL: URL(fileURLWithPath: executablePath()), defaultsDomain: prefsDomain))
}
switch command {
case nil, "-h", "--help", "help":
    print(usage)
    exit(Code.ok)
case "--version", "-V", "version": versionCommand(rest)
case "doctor": doctorCommand(rest)
case "versions": versionsCommand(rest)
case "patch", "restore": writeCommand(command!, rest)
case "settings": settingsCommand(rest)
case "login": loginCommand(rest)
case "logs": logsCommand(rest)
case "config": configCommand(rest)
default: usageError("未知命令 \(command!)", json: arguments.contains("--json"), help: usage)
}
