// Shared command layer for the「配置与更新」window. Opt-in: vendor-lifecycle.py --platform mac --cli.
// Edit only this source. It calls the same AppConfiguration instance logic and AppUpdateChecker as
// AppLifecycleUI, so the window and the product's command line read and write one set of settings.
// It never creates a window, never takes focus and never prompts. `update install --yes` is the only command that
// replaces the app, and it does so through the window's own installer (AppUpgradeInstaller).
#if os(macOS)
import AppKit

/// Wiring, in the product's command dispatcher (same executable as the app, or any Swift CLI built with these files):
///
///     let product = AppLifecycleCLI.Product(command: "clip", name: "Clip",
///                                           configuration: makeConfiguration(), updateSource: updateSource)
///     if AppLifecycleCLI.handles(verb) { return AppLifecycleCLI.run(arguments, product: product) }
///
/// `makeConfiguration()` and `updateSource` must be the ones handed to `AppLifecycleUI.install`.
/// In the app, `AppLifecycleCLI.follow(configuration)` after `install` lets a running window follow command changes.
/// A product whose menu opens this window under its own name (a menu-bar product's「设置…」) also passes
/// `windowEntry: "设置…"` to `Product` and to `helpWindowOnly(windowEntry:)` / `helpNoCommand(windowEntry:)`.
enum AppLifecycleCLI {
    struct Product {
        /// The installed command name, as typed: shown in usage and in `check_with`.
        let command: String
        /// The product name the window title uses.
        let name: String
        /// nil, or no portable settings: the window hides the 配置 group and the commands say so.
        let configuration: AppConfiguration?
        let updateSource: AppUpdateSource
        /// The menu item that opens the window, as this product shows it: named in `config --help` and in `update check`'s `upgrade.how`.
        var windowEntry: String = AppLifecycleCLI.defaultWindowEntry
        /// The app bundle whose version, build and identifier the window shows. Pass the .app when the command is a separate binary.
        var bundle: Bundle = .main
        var out: (String) -> Void = { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) }
        var err: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
        /// PIDs of the running window app; nil looks them up by bundle identifier.
        var runningApp: (() -> [Int32])? = nil
        /// Runs after an import or a toggle, for a product that also has its own cross-process refresh signal.
        var changed: (() -> Void)? = nil
        /// How long a command waits for one sync pass or one release lookup.
        var timeout: TimeInterval = 30
        /// How long `update install` waits for the download and its verification, and then for the replacement itself.
        var upgradeTimeout: TimeInterval = 330
        /// How long `update install` waits for a running app to quit before it gives up without replacing anything.
        var quitTimeout: TimeInterval = 20
    }

    static let verbs = ["config", "update"]
    static func handles(_ verb: String?) -> Bool { verb.map(verbs.contains) ?? false }

    // MARK: Help — splice these into the product's top-level --help so every subcommand is listed there.

    /// What the menu calls the item that opens this window. `AppLifecycleUI` adds it under this name; a product that
    /// opens the window from its own item passes that item's title instead, from one constant of its own.
    static let defaultWindowEntry = "配置与更新…"

    /// Read-only: neither line writes a file or any state, so they can sit under a product heading that promises that.
    static func helpRead(_ command: String) -> String {
        """
          config status              「使用 iCloud 记住配置」开关、开关下面那句同步状态、当前可迁移的配置项、App 是否在运行（只读）
        \(helpUpdate)
        """
    }
    /// The update line alone, for a product that already lists its own `config` commands and wires only `update`.
    static let helpUpdate = "  update check               检查更新：当前版本、此渠道最新版本、有没有新版、怎么升级（只读；私有渠道读 iCloud Drive 里的发行记录，公开渠道联网读发行记录）"
    /// The upgrade line alone, for a product that already lists its own `config` commands and wires only `update`.
    static func helpInstall(_ command: String) -> String {
        "  update install --yes           升级到新版：与窗口「升级到新版…」同一条路——验证发行包与签名、替换当前 App，运行中的先退出、换好再重开；配置保留，替换失败回滚（--dry-run 只看会做什么；用 \(command) update check 回读）"
    }
    /// `config export` is listed here, not under read: it changes no setting, but it does write the file named with -o.
    static func helpWrite(_ command: String) -> String {
        """
          config export -o <file>        导出配置：与窗口「导出配置…」同一份文件；不改设置，只写你指定的那个文件（--force 覆盖；-o - 输出到标准输出，不写文件）
          config import <file> --yes     导入配置：先备份原配置再覆盖，与窗口「导入配置…」相同
          config sync on|off --yes       拨动「使用 iCloud 记住配置」（--dry-run 只看会不会变；用 \(command) config status 回读）
        \(helpInstall(command))
        """
    }
    /// One line for the product's「仅在窗口中」list.
    static let helpWindowOnly = helpWindowOnly(windowEntry: defaultWindowEntry)
    static func helpWindowOnly(windowEntry: String) -> String { "打开「\(windowEntry)」窗口" }
    /// Upgrading has a command now. These stay so a product that still splices them into its help compiles and says
    /// nothing false wherever the line sits; drop the「暂无命令」line and list `helpWrite` / `helpInstall` instead.
    @available(*, deprecated, message: "升级到新版已有命令：删掉帮助里的「暂无命令」这行，改列 helpWrite 或 helpInstall；登记改 command: <命令> update install")
    static let helpNoCommand = "升级到新版已有命令：update install --yes"
    @available(*, deprecated, message: "升级到新版已有命令：删掉帮助里的「暂无命令」这行，改列 helpWrite 或 helpInstall；登记改 command: <命令> update install")
    static func helpNoCommand(windowEntry: String) -> String { "升级到新版已有命令：update install --yes" }

    static func help(_ command: String, windowEntry: String = defaultWindowEntry) -> String {
        """
        usage: \(command) config [status] [--json]
               \(command) config export -o <file.json> [--force] [--json]
               \(command) config import <file.json> --yes [--json]
               \(command) config sync on|off --yes [--dry-run] [--json]
               \(command) update check [--json]
               \(command) update install --yes [--dry-run] [--json]
        「\(windowEntry)」窗口里的各项，与窗口读写同一份设置、走同一个安装器。
        读（不写任何文件或状态）:
        \(helpRead(command))
        写:
        \(helpWrite(command))
        --json：成功 {"ok": true, "command": "config status", …}；失败 {"ok": false, "command": …, "error": {"code", "message"}}，退出码非零。
          config status  → has_settings, sync_enabled, sync_status{text, at, from, live}, keys[], app_running, problem
          config export  → path, bytes, keys[]
          config import  → imported, path, sync_enabled, app_running, sync{completed, status}（仅同步开着时）
          config sync    → action, changed, sync_enabled, status, app_running, check_with；--dry-run 给 would_change
          update check   → current{version, build}, source{kind, …}, latest{version, build, …}, update_available,
                           state（update_available | up_to_date | ahead_of_channel）, message, upgrade{in_app, button, how, download_url, command}
          update install → installed, state（installed | up_to_date | ahead_of_channel | handed_off）, message, current, latest, source, app_running；
                           装上后另有 previous{version, build}, backup（成功为 null）, old_app_cleanup, relaunched；--dry-run 给 would_install{from, to}, installation, will_quit_app, will_relaunch
        sync_status 是窗口开关下面那句话。from：app（运行中的 App 此刻显示的，live 为 true）· record（App 没在运行，上一次同步留下的那句，at 是当时）·
          derived（没有可用的记录，按开关给窗口打开时的初值）
        退出码与 error.code：
          0  成功（update install 没有新版时也是 0，installed 为 false）
          1  操作未完成：not_found（没有这个文件）· import_rejected（导入被拒，原配置保留）· export_failed（导出未完成）·
             sync_incomplete（开关已打开，首次同步未完成）· check_incomplete（没读到发行记录）· no_settings（没有可迁移配置）·
             manual_install（此渠道或此安装位置不能由命令替换，给出安装包地址）· needs_product_installer（此产品要走自己的安装事务）·
             upgrade_failed（下载或验证未通过，当前 App 未动）· app_busy（运行中的 App 没有退出，未替换）·
             replace_failed（替换未完成，旧版已保留或已回滚）· cleanup_failed（新版已验证，旧包清理失败并保留）· failed（其他）
          2  用法错误或缺确认参数：usage（参数不对）· confirmation_required（import、sync、update install 缺 --yes）· file_exists（导出目标已存在，缺 --force）
        仅在窗口中：\(helpWindowOnly(windowEntry: windowEntry))
        命令不弹窗、不抢焦点、不申请权限；升级要带 --yes。
        """
    }

    // MARK: Entry

    /// `arguments` starts at the verb: ["config", "status", "--json"]. Call on the main thread; returns the exit code.
    static func run(_ arguments: [String], product: Product) -> Int32 {
        let json = arguments.contains("--json")
        var command = arguments.first ?? ""
        do {
            guard let verb = arguments.first, verbs.contains(verb) else { throw Failure.usage(syntax(product.command)) }
            let p = try parse(Array(arguments.dropFirst()))
            let sub = p.positionals.first ?? (verb == "config" ? "status" : "")
            command = sub.isEmpty ? verb : verb + " " + sub
            if p.flags.contains("--help") || p.flags.contains("-h") { product.out(help(product.command, windowEntry: product.windowEntry)); return 0 }
            // A command's own sync results go to its own record: it never replaces the sentence the running window shows.
            product.configuration?.statusRecordName = commandStatusRecord
            let result: Output
            switch (verb, sub) {
            case ("config", "status"): result = try configStatus(p, product)
            case ("config", "export"): result = try configExport(p, product, json: json)
            case ("config", "import"): result = try configImport(p, product)
            case ("config", "sync"): result = try configSync(p, product)
            case ("update", "check"): result = try updateCheck(p, product)
            case ("update", "install"): result = try updateInstall(p, product)
            default: throw Failure.usage(syntax(product.command))
            }
            if json {
                var body = result.body
                body["ok"] = true; body["command"] = command
                product.out(text(body))
            } else { product.out(result.text) }
            return 0
        } catch let failure as Failure {
            if json {
                var body = failure.extra
                body["ok"] = false; body["command"] = command
                body["error"] = ["code": failure.code, "message": failure.message]
                product.out(text(body))
            } else { product.err(failure.message) }
            return failure.exit
        } catch {
            let failure = Failure(exit: 1, code: "failed", message: error.localizedDescription)
            if json { product.out(text(["ok": false, "command": command, "error": ["code": failure.code, "message": failure.message]])) }
            else { product.err(failure.message) }
            return failure.exit
        }
    }

    /// App side, one line after `AppLifecycleUI.install`: a running window follows what the command line changed.
    /// The command is the only writer of the switch; the app never stores it here, neither its own reading nor the
    /// value the command announced. Preferences written by another process reach this one late, and a second command
    /// may already have changed the switch again: either write would undo a command. (Storing the announced value
    /// after the delay did exactly that on a running LiteGauge, 2026-10-07: `sync on` then `sync off` back to back,
    /// and a fresh process read 开 again after `sync off` had returned.)
    /// The app waits until its own reading agrees with what the newest command announced, then runs the non-writing
    /// half of the window's path: `reconcile()` starts syncing when the switch is on and reports 已关闭 when it is off,
    /// and its status notification refreshes the switch and the status line. Only the newest notification acts.
    /// An import announces no switch state. The product's `onChange` then re-reads imported settings.
    static func follow(_ configuration: AppConfiguration?, bundle: Bundle = .main) {
        guard let configuration, let name = notification(bundle) else { return }
        followers.append(DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { [weak configuration] note in
            if let state = switchState(note.object as? String) { announced = state }
            newest += 1
            adopt(configuration, turn: newest, attempt: 0)
        })
    }
    private static var newest = 0
    private static var announced: Bool?
    private static func adopt(_ configuration: AppConfiguration?, turn: Int, attempt: Int) {
        // Settings written by the other process reach this one a moment after the notification.
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.3 : 0.1)) { [weak configuration] in
            guard let configuration, turn == newest else { return }   // a newer command's notification takes over
            if let expected = announced, configuration.enabled != expected, attempt < 30 {
                adopt(configuration, turn: turn, attempt: attempt + 1); return
            }
            announced = nil
            configuration.start()       // no-op once started; the observers sync needs
            configuration.reconcile()   // reads the stored switch, never writes it
            configuration.onChange?()
        }
    }

    // MARK: config

    private static func configStatus(_ p: Arguments, _ product: Product) throws -> Output {
        guard p.positionals.count <= 1, p.output == nil else { throw Failure.usage(syntax(product.command)) }
        let configuration = product.configuration
        let has = configuration?.hasSettings == true
        let enabled = has && configuration?.enabled == true
        let app = !running(product).isEmpty
        var keys: [String] = [], problem: Any = NSNull()
        if has, let configuration {
            // The export is the window's own read of the allowlisted values; it writes nothing.
            do { keys = try exportedKeys(configuration.exportData()) } catch { problem = error.localizedDescription }
        }
        var sentence = !has ? "\(product.name) 没有可迁移的配置"
            : "使用 iCloud 记住配置：\(enabled ? "开" : "关") · 可迁移的配置项 \(keys.count) 个" + (keys.isEmpty ? "" : "：" + keys.joined(separator: " "))
        var shown: Any = NSNull()
        if has, let configuration {
            let status = syncStatus(configuration, enabled: enabled, running: running(product))
            shown = status
            sentence += "\n同步状态：\(status["text"] ?? "")" + (status["live"] as? Bool == true ? "（运行中的 App 此刻显示）" : "")
        }
        return Output(body: ["has_settings": has, "sync_enabled": enabled, "sync_status": shown, "keys": keys, "app_running": app, "problem": problem],
                      text: sentence + (problem is NSNull ? "" : "\n读取配置时遇到问题：\(problem)"))
    }

    /// Where a command process records its own sync results (`run` sets it). A product that keeps its own `config`
    /// commands sets `configuration.statusRecordName` to this in its command process before it syncs.
    static let commandStatusRecord = "status-command.json"
    /// The sentence under the window's switch, read without a window: `sync_status` of `config status`. Writes nothing.
    /// `running` is the pids of the window app. Not private, for a product whose own `config status` reports it too.
    static func syncStatus(_ configuration: AppConfiguration, enabled: Bool, running: [Int32]) -> [String: Any] {
        // What a window shows before its first pass, and all it ever shows while the switch is off.
        let closed = "iCloud 配置同步已关闭", initial = enabled ? "等待 iCloud 配置同步" : closed
        func stamp(_ at: TimeInterval) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = .current
            return formatter.string(from: Date(timeIntervalSince1970: at))
        }
        let app = configuration.statusRecord()
        if !running.isEmpty {
            // Only a record the running app wrote is its sentence; until it publishes one, it shows the initial value.
            if let app, running.contains(app.pid) { return ["text": app.status, "at": stamp(app.at), "from": "app", "live": true] }
            return ["text": initial, "at": NSNull(), "from": "derived", "live": true]
        }
        // Nobody is showing a sentence: the newest result left behind, unless the switch has changed under it since.
        let latest = [app, configuration.statusRecord(named: commandStatusRecord)].compactMap { $0 }.max { $0.at < $1.at }
        if let latest, (latest.status == closed) == !enabled { return ["text": latest.status, "at": stamp(latest.at), "from": "record", "live": false] }
        return ["text": initial, "at": NSNull(), "from": "derived", "live": false]
    }

    private static func configExport(_ p: Arguments, _ product: Product, json: Bool) throws -> Output {
        guard p.positionals.count == 1, let raw = p.output else { throw Failure.usage(syntax(product.command)) }
        let configuration = try portable(product)
        let data: Data
        do { data = try configuration.exportData() }
        catch { throw Failure(exit: 1, code: "export_failed", message: "导出未完成：" + error.localizedDescription) }
        let keys = (try? exportedKeys(data)) ?? []
        if raw == "-" {
            guard !json else { throw Failure.usage("-o - 把配置本身写到标准输出，不能与 --json 同用") }
            return Output(body: [:], text: String(decoding: data, as: UTF8.self))
        }
        let url = file(raw)
        guard p.flags.contains("--force") || !FileManager.default.fileExists(atPath: url.path) else {
            throw Failure(exit: 2, code: "file_exists", message: "\(url.path) 已存在；加 --force 覆盖")
        }
        do { try data.write(to: url, options: .atomic) }
        catch { throw Failure(exit: 1, code: "export_failed", message: "导出未完成：" + error.localizedDescription) }
        return Output(body: ["path": url.path, "bytes": data.count, "keys": keys], text: "配置已导出：\(url.path)")
    }

    private static func configImport(_ p: Arguments, _ product: Product) throws -> Output {
        guard p.positionals.count == 2, p.output == nil else { throw Failure.usage(syntax(product.command)) }
        let configuration = try portable(product)
        let url = file(p.positionals[1])
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw Failure(exit: 1, code: "not_found", message: "没有文件 \(url.path)")
        }
        guard p.flags.contains("--yes") else {
            throw Failure(exit: 2, code: "confirmation_required", message: "导入会覆盖当前可迁移的配置（原配置自动备份）：确认请加 --yes")
        }
        do { try configuration.importData(data) }
        catch { throw Failure(exit: 1, code: "import_rejected", message: "导入未完成，原配置已保留：" + error.localizedDescription) }
        var body: [String: Any] = ["imported": true, "path": url.path, "sync_enabled": configuration.enabled, "app_running": !running(product).isEmpty]
        var sentence = "已导入；原配置已备份。"
        if configuration.enabled {
            // Same as the window: an import made while sync is on is carried to iCloud; an offline import keeps its intent for the next pass.
            let pass = sync(configuration, timeout: product.timeout)
            body["sync"] = ["completed": pass.completed, "status": pass.status]
            sentence += pass.completed ? "已同步到 iCloud。" : "同步未完成，下次同步时继续：\(pass.status)"
        }
        notify(product, switchedTo: nil)
        return Output(body: body, text: sentence)
    }

    private static func configSync(_ p: Arguments, _ product: Product) throws -> Output {
        guard p.positionals.count == 2, p.output == nil, let target = ["on": true, "off": false][p.positionals[1]] else {
            throw Failure.usage(syntax(product.command))
        }
        let configuration = try portable(product)
        let before = configuration.enabled, word = target ? "开" : "关"
        var body: [String: Any] = ["action": target ? "on" : "off", "app_running": !running(product).isEmpty,
                                   "check_with": "\(product.command) config status"]
        if p.flags.contains("--dry-run") {
            body["dry_run"] = true; body["would_change"] = before != target; body["sync_enabled"] = before
            return Output(body: body, text: before == target ? "「使用 iCloud 记住配置」已是\(word)，不会改动" : "将把「使用 iCloud 记住配置」拨到\(word)（未执行）")
        }
        if before == target {
            body["changed"] = false; body["sync_enabled"] = before
            return Output(body: body, text: "「使用 iCloud 记住配置」已是\(word)")
        }
        guard p.flags.contains("--yes") else {
            throw Failure(exit: 2, code: "confirmation_required",
                          message: "会\(target ? "开始把配置同步到" : "停止把配置同步到")你的 iCloud：确认请加 --yes（或先 --dry-run）")
        }
        // The switch's own action: stores the choice and, when turned on, starts the first sync.
        configuration.setEnabled(target)
        let pass = target ? sync(configuration, timeout: product.timeout) : settle(configuration)
        flush(configuration)
        notify(product, switchedTo: target)
        body["changed"] = true; body["sync_enabled"] = configuration.enabled; body["status"] = pass.status
        guard pass.completed else {
            body.removeValue(forKey: "action")
            throw Failure(exit: 1, code: "sync_incomplete", message: "开关已打开，首次同步未完成：\(pass.status)", extra: body)
        }
        return Output(body: body, text: "「使用 iCloud 记住配置」已\(target ? "打开" : "关闭")：\(pass.status)")
    }

    // MARK: update

    /// One release lookup and the window's three outcomes and sentences (AppLifecycleUI.checkForUpdates).
    private struct Checked {
        let version: String, build: String, current: [String: Any], source: [String: Any]
        let release: AppRelease, state: String, message: String
        var newer: Bool { state == "update_available" }
        var latest: [String: Any] {
            ["version": release.version, "build": release.build, "channel": release.channel ?? NSNull(),
             "download_url": release.downloadURL?.absoluteString ?? NSNull(), "release_url": release.releaseURL?.absoluteString ?? NSNull(),
             "sha256": release.sha256 ?? NSNull(), "size_bytes": release.size ?? NSNull()]
        }
    }
    private static func checked(_ product: Product) throws -> Checked {
        let bundle = product.bundle
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let current: [String: Any] = ["version": version, "build": build]
        let source = describe(product.updateSource)
        let box = Box<Result<AppRelease, Error>>()
        AppUpdateChecker.check(source: product.updateSource, bundleID: bundle.bundleIdentifier ?? "", version: version, build: build) { box.set($0) }
        wait(product.timeout) { box.value != nil }
        let release: AppRelease
        switch box.value {
        case .none:
            throw Failure(exit: 1, code: "check_incomplete", message: "检查未完成：\(Int(product.timeout)) 秒内没有读到发行记录", extra: ["current": current, "source": source])
        case .failure(let error)?:
            throw Failure(exit: 1, code: "check_incomplete", message: "检查未完成：" + error.localizedDescription, extra: ["current": current, "source": source])
        case .success(let value)?: release = value
        }
        let state: String, message: String
        if release.isNewer(than: version, build: build) {
            state = "update_available"; message = "有新版 \(release.version) (\(release.build))，当前 \(version) (\(build))。升级会保留本机配置。"
        } else if AppVersion.compare(version, release.version) == .orderedDescending {
            state = "ahead_of_channel"; message = "当前 \(version) (\(build))；此渠道正式发行版本为 \(release.version) (\(release.build))。"
        } else { state = "up_to_date"; message = "当前已是此渠道最新版：\(version) (\(build))。" }
        return Checked(version: version, build: build, current: current, source: source, release: release, state: state, message: message)
    }

    private static func updateCheck(_ p: Arguments, _ product: Product) throws -> Output {
        guard p.positionals.count == 1, p.output == nil else { throw Failure.usage(syntax(product.command)) }
        let check = try checked(product), release = check.release, newer = check.newer
        let inApp = newer && AppUpgradeInstaller.supportsReplacement(release: release, currentBundle: product.bundle.bundleURL)
        let link = release.downloadURL.flatMap { $0.isFileURL ? nil : $0.absoluteString }
        let install = "\(product.command) update install --yes"
        let how: String
        if !newer { how = "不需要升级。" }
        else if release.downloadURL == nil { how = "此渠道没有给出安装包" + (release.releaseURL.map { "；到发行页获取：\($0.absoluteString)" } ?? "。") }
        else if inApp { how = "运行 \(install)（先加 --dry-run 可只看会做什么），或打开 \(product.name)，在菜单里选「\(product.windowEntry)」→「检查更新」→「升级到新版…」并确认：两条路相同，会验证发行包与签名、替换当前 App 并重新打开，配置保留，替换失败可回滚。" }
        else { how = "打开 \(product.name)，在「\(product.windowEntry)」里点「下载新版…」" + (link.map { "，或直接下载安装包：\($0)" } ?? "") + "；安装新版会保留支持目录中的配置。这个安装位置或渠道不能由命令替换。" }
        let upgrade: [String: Any] = ["in_app": inApp, "button": !newer || release.downloadURL == nil ? NSNull() : (inApp ? "升级到新版…" : "下载新版…") as Any,
                                      "how": how, "download_url": link ?? NSNull(), "command": inApp ? install : NSNull() as Any]
        return Output(body: ["current": check.current, "source": check.source, "latest": check.latest, "update_available": newer, "state": check.state,
                             "message": check.message, "upgrade": upgrade],
                      text: check.message + (newer ? "\n" + how : ""))
    }

    /// The window's「升级到新版…」: the same lookup, the same download, verification and replacement (AppUpgradeInstaller).
    /// The window asks in a sheet; the command asks for --yes. The window quits itself and lets the helper reopen it;
    /// the command quits the running app, waits for the replacement to finish and reports what is on disk afterwards.
    private static func updateInstall(_ p: Arguments, _ product: Product) throws -> Output {
        guard p.positionals.count == 1, p.output == nil else { throw Failure.usage(syntax(product.command)) }
        let check = try checked(product), release = check.release
        // Read before anything is replaced; nothing below goes back to the bundle object for a version.
        let target = product.bundle.bundleURL, identifier = product.bundle.bundleIdentifier
        let apps = running(product, identifier: identifier)
        var body: [String: Any] = ["current": check.current, "source": check.source, "latest": check.latest, "app_running": !apps.isEmpty]
        guard check.newer else {
            body["installed"] = false; body["state"] = check.state; body["message"] = check.message
            return Output(body: body, text: check.message + "不需要升级。")
        }
        let link = release.downloadURL.flatMap { $0.isFileURL ? nil : $0.absoluteString }
        guard release.downloadURL != nil, AppUpgradeInstaller.supportsReplacement(release: release, currentBundle: target) else {
            // Here the window's button is「下载新版…」: it only opens the package address.
            body["download_url"] = link ?? NSNull(); body["release_url"] = release.releaseURL?.absoluteString ?? NSNull()
            let where_ = link.map { "下载安装包：\($0)" } ?? release.releaseURL.map { "到发行页获取：\($0.absoluteString)" } ?? "此渠道没有给出安装包"
            throw Failure(exit: 1, code: "manual_install", message: "有新版 \(release.version) (\(release.build))，但这个安装位置或渠道不能由命令替换（窗口里是「下载新版…」）。\(where_)；装上后配置保留。", extra: body)
        }
        let recipe = release.installation ?? "bundle"
        guard recipe == "bundle" || recipe == "notifhub-collector" else {
            body["installation"] = recipe
            throw Failure(exit: 1, code: "needs_product_installer", message: "此产品需要其专用安装事务：\(recipe)", extra: body)
        }
        let plan: [String: Any] = ["from": check.current, "to": ["version": release.version, "build": release.build]]
        if p.flags.contains("--dry-run") {
            body["dry_run"] = true; body["installed"] = false; body["state"] = check.state; body["would_install"] = plan; body["installation"] = recipe
            body["will_quit_app"] = !apps.isEmpty; body["will_relaunch"] = !apps.isEmpty; body["message"] = check.message
            return Output(body: body, text: "将从 \(check.version) (\(check.build)) 升级到 \(release.version) (\(release.build))（未执行）"
                          + (apps.isEmpty ? "；App 没在运行，换好后不会打开它。" : "；运行中的 \(product.name) 会先退出，换好后重新打开。"))
        }
        guard p.flags.contains("--yes") else {
            throw Failure(exit: 2, code: "confirmation_required",
                          message: "会验证发行包与签名，然后把当前的 \(product.name) \(check.version) (\(check.build)) 替换为 \(release.version) (\(release.build))；运行中的会先退出、换好再重开，配置保留，替换失败回滚：确认请加 --yes（或先 --dry-run）")
        }
        let box = Box<Result<AppUpgradeInstaller.Prepared, Error>>()
        AppUpgradeInstaller.prepare(release: release, currentBundle: target) { box.set($0) }
        wait(product.upgradeTimeout) { box.value != nil }
        let prepared: AppUpgradeInstaller.Prepared
        switch box.value {
        case .none:
            throw Failure(exit: 1, code: "upgrade_failed", message: "升级未完成，当前 App 已保留：\(Int(product.upgradeTimeout)) 秒内没有完成下载与验证", extra: body)
        case .failure(let error)?:
            throw Failure(exit: 1, code: "upgrade_failed", message: "升级未完成，当前 App 已保留：" + error.localizedDescription, extra: body)
        case .success(let value)?: prepared = value
        }
        func discard() { try? FileManager.default.removeItem(at: prepared.directory) }
        if recipe == "notifhub-collector" {
            // The product's own install transaction, started the way the window starts it: it waits for the process it is
            // given, so a running app is asked to quit after the hand-off, as the window quits itself.
            do { try AppUpgradeInstaller.launchReplacement(prepared, currentBundle: target, pid: apps.first ?? ProcessInfo.processInfo.processIdentifier) }
            catch { discard(); throw Failure(exit: 1, code: "replace_failed", message: "无法开始替换，当前 App 已保留：" + error.localizedDescription, extra: body) }
            quit(apps)
            body["installed"] = false; body["handed_off"] = true; body["state"] = "handed_off"; body["installation"] = recipe
            body["check_with"] = "\(product.command) update check"
            body["message"] = "发行包已验证，已交给 \(product.name) 自己的安装事务。"
            return Output(body: body, text: "发行包已验证，已交给 \(product.name) 自己的安装事务；稍后用 \(product.command) update check 回读。")
        }
        // An ordinary bundle. The helper must not swap a bundle a running app still executes from.
        quit(apps)
        wait(product.quitTimeout) { !alive(apps) }
        guard !alive(apps) else {
            discard()
            throw Failure(exit: 1, code: "app_busy", message: "运行中的 \(product.name) 没有在 \(Int(product.quitTimeout)) 秒内退出（可能有未保存的内容或正在忙），没有替换，当前 App 未动。", extra: body)
        }
        let relaunch = !apps.isEmpty
        var restored = false
        func fail(_ message: String, log: String? = nil) -> Failure {
            // What the helper leaves beside the app when it stops before the swap.
            try? FileManager.default.removeItem(atPath: String(target.path.dropLast(".app".count)) + ".upgrade-0.app")
            if relaunch && !alive(apps) && FileManager.default.fileExists(atPath: target.path) { restored = reopen(target) }
            var extra = body
            extra["relaunched"] = restored; extra["log"] = log ?? NSNull()
            return Failure(exit: 1, code: "replace_failed", message: message, extra: extra)
        }
        let launched: (process: Process, backup: URL?, reopens: Bool)
        do { launched = try AppUpgradeInstaller.launchReplacement(prepared, currentBundle: target, pid: 0, relaunch: relaunch) }
        catch { discard(); throw fail("无法开始替换，当前 App 已保留：" + error.localizedDescription) }
        wait(product.upgradeTimeout) { !launched.process.isRunning }
        guard !launched.process.isRunning else { throw fail("替换没有在 \(Int(product.upgradeTimeout)) 秒内结束，没有再等；用 \(product.command) update check 回读当前版本。") }
        if launched.process.terminationStatus == 2 {
            let log = (try? String(contentsOf: prepared.directory.appendingPathComponent("install.log"), encoding: .utf8)).map { String($0.suffix(2000)) }
            var extra = body
            let installed = NSDictionary(contentsOf: target.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
            extra["installed"] = true; extra["current"] = ["version": installed?["CFBundleShortVersionString"] as? String ?? "0", "build": installed?["CFBundleVersion"] as? String ?? "0"]
            if let retained = launched.backup, FileManager.default.fileExists(atPath: retained.path) {
                extra["backup"] = retained.path
            } else {
                extra["backup"] = NSNull()
            }
            extra["receipt_directory"] = prepared.directory.path
            extra["old_app_cleanup"] = "failed"; extra["relaunched"] = launched.reopens; extra["log"] = log ?? NSNull()
            throw Failure(exit: 1, code: "cleanup_failed", message: "新版已验证，但旧 App 清理失败，原件与安装日志已保留。", extra: extra)
        }
        guard launched.process.terminationStatus == 0 else {
            let log = (try? String(contentsOf: prepared.directory.appendingPathComponent("install.log"), encoding: .utf8)).map { String($0.suffix(2000)) }
            throw fail("替换未完成，旧版已保留或已回滚。" + (log.map { $0.isEmpty ? "" : "\n" + $0 } ?? ""), log: log)
        }
        // From disk: the bundle object read before the swap still describes the old app.
        let info = NSDictionary(contentsOf: target.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        let now: [String: Any] = ["version": info?["CFBundleShortVersionString"] as? String ?? "0", "build": info?["CFBundleVersion"] as? String ?? "0"]
        guard now["version"] as? String == release.version, release.build == "0" || now["build"] as? String == release.build else {
            throw fail("替换结束了，但磁盘上的版本是 \(now["version"] ?? "?") (\(now["build"] ?? "?"))，不是 \(release.version) (\(release.build))。")
        }
        body["installed"] = true; body["state"] = "installed"; body["previous"] = check.current; body["current"] = now
        body["backup"] = NSNull(); body["old_app_cleanup"] = "trashed"; body["relaunched"] = launched.reopens
        body["message"] = "已升级到 \(release.version) (\(release.build))。"
        return Output(body: body, text: "已从 \(check.version) (\(check.build)) 升级到 \(release.version) (\(release.build))；配置保留"
                      + "，旧 App 已移到废纸篓" + (launched.reopens ? "；\(product.name) 已重新打开。" : "。"))
    }

    /// Asks each running instance to quit, the way the app's own Quit does. A process that is not an application to the
    /// system (a windowless helper) gets SIGTERM.
    private static func quit(_ pids: [Int32]) {
        for pid in pids {
            if let app = NSRunningApplication(processIdentifier: pid) { app.terminate() } else { kill(pid, SIGTERM) }
        }
    }
    private static func alive(_ pid: Int32) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid) { return !app.isTerminated }
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        // A process that has exited but that its parent has not collected yet still answers kill(0); it runs nothing.
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid], info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.stride
        if sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0, Int32(info.kp_proc.p_stat) == SZOMB { return false }
        return true
    }
    private static func alive(_ pids: [Int32]) -> Bool { pids.contains(where: alive) }
    /// Puts back an app this command asked to quit when the replacement did not happen. Never in an isolated run.
    private static func reopen(_ app: URL) -> Bool {
        guard ProcessInfo.processInfo.environment["APP_LIFECYCLE_NO_RELAUNCH"] != "1" else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open"); process.arguments = ["-g", "-j", app.path]
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: Plumbing

    private struct Output { let body: [String: Any]; let text: String }
    private struct Failure: Error {
        let exit: Int32
        let code: String
        let message: String
        var extra: [String: Any] = [:]
        static func usage(_ message: String) -> Failure { Failure(exit: 2, code: "usage", message: message) }
    }
    private struct Arguments { var positionals: [String] = []; var flags: Set<String> = []; var output: String? }
    private final class Box<T> {
        private let lock = NSLock()
        private var stored: T?
        var value: T? { lock.lock(); defer { lock.unlock() }; return stored }
        func set(_ value: T) { lock.lock(); stored = value; lock.unlock() }
    }
    private static var followers: [NSObjectProtocol] = []

    private static func syntax(_ command: String) -> String {
        "用法：\(command) config status | export -o <file> [--force] | import <file> --yes | sync on|off --yes [--dry-run]；\(command) update check | install --yes [--dry-run]（都可加 --json）"
    }

    private static func parse(_ arguments: [String]) throws -> Arguments {
        var parsed = Arguments(), index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--json", "--yes", "--dry-run", "--force", "--help", "-h": parsed.flags.insert(argument)
            case "-o", "--output":
                guard index + 1 < arguments.count else { throw Failure.usage("\(argument) 后面要跟文件路径") }
                index += 1; parsed.output = arguments[index]
            default:
                if argument.hasPrefix("--output=") { parsed.output = String(argument.dropFirst("--output=".count)) }
                else if argument.hasPrefix("-") { throw Failure.usage("未知参数 \(argument)") }
                else { parsed.positionals.append(argument) }
            }
            index += 1
        }
        return parsed
    }

    private static func portable(_ product: Product) throws -> AppConfiguration {
        guard let configuration = product.configuration, configuration.hasSettings else {
            throw Failure(exit: 1, code: "no_settings", message: "\(product.name) 没有可迁移的配置（窗口里也没有「配置」这一组）")
        }
        return configuration
    }
    private static func file(_ raw: String) -> URL { URL(fileURLWithPath: (raw as NSString).expandingTildeInPath) }
    private static func exportedKeys(_ data: Data) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return ((object?["values"] as? [String: Any]) ?? [:]).keys.sorted()
    }
    private static func text(_ body: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])) ?? Data("{\"ok\":false}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
    private static func describe(_ source: AppUpdateSource) -> [String: Any] {
        switch source {
        case .github(let repository): return ["kind": "github", "repository": repository]
        case .manifest(let url): return ["kind": "manifest", "url": url.absoluteString]
        case .privateCloud(let channel): return ["kind": "private_cloud", "channel": channel]
        case .appStore(let id): return ["kind": "app_store", "id": id]
        }
    }
    private static func running(_ product: Product) -> [Int32] { running(product, identifier: product.bundle.bundleIdentifier) }
    private static func running(_ product: Product, identifier: String?) -> [Int32] {
        if let custom = product.runningApp { return custom() }
        guard let identifier else { return [] }
        let own = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).map(\.processIdentifier).filter { $0 != own }
    }

    /// Completions and status are delivered on the main queue, so the main thread keeps its run loop turning while it waits.
    private static func wait(_ seconds: TimeInterval, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    }
    /// One explicit pass of the shared reconcile; `status` is the sentence the window would show for it.
    private static func sync(_ configuration: AppConfiguration, timeout: TimeInterval) -> (completed: Bool, status: String) {
        let box = Box<Error?>()
        configuration.reconcile { box.set($0) }
        wait(timeout) { box.value != nil }
        guard let finished = box.value else { return (false, "\(Int(timeout)) 秒内同步没有结束") }
        return (finished == nil, configuration.status)
    }
    private static func settle(_ configuration: AppConfiguration) -> (completed: Bool, status: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        return (true, configuration.status)
    }
    /// The export's first step flushes the configuration's own preferences object; a short-lived process must not exit before that.
    private static func flush(_ configuration: AppConfiguration) { _ = try? configuration.exportData() }

    /// Isolated runs (self-tests) never reach a running app. A test that starts its own follower process names a private
    /// channel in APP_LIFECYCLE_FOLLOW_CHANNEL; both sides then use that name instead of the bundle identifier.
    private static func notification(_ bundle: Bundle) -> Notification.Name? {
        let environment = ProcessInfo.processInfo.environment, prefix = "cyou.tianli.lifecycle.configuration-changed."
        if let channel = environment["APP_LIFECYCLE_FOLLOW_CHANNEL"], !channel.isEmpty { return Notification.Name(prefix + channel) }
        guard environment["APP_LIFECYCLE_SUPPORT_DIR"] == nil, let identifier = bundle.bundleIdentifier else { return nil }
        return Notification.Name(prefix + identifier)
    }
    /// The switch state travels as the notification's object string: a sandboxed sender may not attach a dictionary.
    private static func switchState(_ object: String?) -> Bool? { object.flatMap { ["sync=on": true, "sync=off": false][$0] } }
    private static func notify(_ product: Product, switchedTo state: Bool?) {
        product.changed?()
        guard let name = notification(product.bundle) else { return }
        DistributedNotificationCenter.default().postNotificationName(name, object: state.map { $0 ? "sync=on" : "sync=off" }, userInfo: nil, deliverImmediately: true)
    }
}
#endif
