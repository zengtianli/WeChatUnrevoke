import Foundation
import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications

// =============================================================================
// AppModel — 全部状态与流程
//
// 三条铁律：
//  1. 判决不在这里算。`status.overall` 来自引擎，这里只渲染和分派动作。
//  2. 任何会写微信的动作，前提条件（微信没在跑 / 要不要密码）都由**这一次**的
//     doctor 结果决定，不用上一次缓存的 —— 用户可能刚把微信打开。
//  3. 自动重打只在「不需要密码、微信没开、而且用户之前确实打过」时发生。
//     够不着这三条就只发通知，绝不背着人弹授权框。
// =============================================================================

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var status: DoctorStatus?
    @Published private(set) var isBusy = false
    @Published private(set) var busyMessage = ""
    @Published private(set) var lastLog = ""
    @Published var errorMessage: String?
    @Published var toast: String?
    @Published var variant: PatchVariant {
        didSet { defaults.set(variant.rawValue, forKey: Keys.variant) }
    }
    @Published var autoRepatch: Bool {
        didSet {
            defaults.set(autoRepatch, forKey: Keys.autoRepatch)
            if autoRepatch { Task { await requestNotificationPermission() } }
        }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    private let engine = Engine()
    private let defaults = UserDefaults.standard
    private let confirmAction: ((String, String, String) -> Bool)?
    private var lastWriteError: String?
    private var automaticWriteBlocked = false
    private var writeGeneration = 0
    private var timer: Timer?
    private var checkedFingerprint: String?
    private var lastFullCheck = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    private enum Keys {
        static let variant = "variant"
        static let autoRepatch = "autoRepatch"
        static let lastBuild = "lastBuild"
        /// 用户上一次成功打过补丁 —— 自动重打的前提，避免对「从没用过」的人自作主张。
        static let everProtected = "everProtected"
    }

    init(confirmAction: ((String, String, String) -> Bool)? = nil) {
        self.confirmAction = confirmAction
        variant = PatchVariant(rawValue: defaults.string(forKey: Keys.variant) ?? "") ?? .keeptip
        autoRepatch = defaults.object(forKey: Keys.autoRepatch) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - 生命周期

    func start() {
        // 先体检再联网：拉 config.json 最长要 15 秒，让界面先干等着那 15 秒
        // 是在拿一个「大多数时候没变化」的更新，换掉整个首屏。
        Task {
            await refresh()
            if await engine.refreshConfig() {
                toast = L.foot_configUpdated
                await refresh()
            }
        }
        // 微信起停会改变「能不能打补丁」，所以两个事件都要重新看一眼。
        let wc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(wc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Engine.wechatBundleID else { return }
                Task { @MainActor in await self?.refresh() }
            })
        }
        // 微信的更新是整包替换，没有事件可听，只能定时看。60s 足够——
        // 更新后用户总要重开微信，那一下也会触发上面的事件。
        // 每一跳只 stat 几个文件；包没变就不起引擎（见 periodicCheck）。
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.periodicCheck() }
        }
        timer?.tolerance = 15
    }

    /// 定时检查：微信包的文件指纹与上次完整体检时一样，就跳过这一次。
    /// 一次 `doctor` 要起 codesign/csrutil 等子进程，实测约 1.4 秒、0.25 秒 CPU；
    /// stat 五个路径不到 1 毫秒。更新（整包替换）、打补丁/还原（改 dylib、重签）、
    /// 改属主或权限都会改变指纹；指纹覆盖不到的变化（系统授权、微信偏好）
    /// 靠每 30 分钟一次的完整体检兜底，用户也可以随时 ⌘R。
    func periodicCheck() async {
        if let current = AppModel.bundleFingerprint(Engine.weChatPath), current == checkedFingerprint,
           Date().timeIntervalSince(lastFullCheck) < AppModel.fullCheckInterval {
            return
        }
        await refresh()
    }

    static let fullCheckInterval: TimeInterval = 30 * 60

    /// 会随「更新 / 打补丁 / 还原 / 重签 / 改权限」变化的几个路径的 inode、大小、
    /// 修改与状态变更时间。包不存在返回 nil（交给 refresh 报「找不到微信」）。
    static func bundleFingerprint(_ appPath: String) -> String? {
        let parts = ["", "/Contents/Info.plist", "/Contents/MacOS/WeChat",
                     "/Contents/Resources/wechat.dylib", "/Contents/_CodeSignature/CodeResources"]
        var out: [String] = []
        for (index, part) in parts.enumerated() {
            var st = stat()
            guard stat(appPath + part, &st) == 0 else {
                if index == 0 { return nil }
                out.append("-")
                continue
            }
            out.append("\(st.st_ino):\(st.st_size):\(st.st_mode):\(st.st_uid):"
                + "\(st.st_mtimespec.tv_sec).\(st.st_mtimespec.tv_nsec):"
                + "\(st.st_ctimespec.tv_sec).\(st.st_ctimespec.tv_nsec)")
        }
        return out.joined(separator: "|")
    }

    func stop() {
        timer?.invalidate()
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
    }

    // MARK: - 只读检查

    func refresh(duringWrite: Bool = false) async {
        // Signing temporarily changes entitlements. Background checks must not
        // publish an intermediate bundle state or overwrite the final write check.
        guard !isBusy || duringWrite else { return }
        let generation = writeGeneration
        guard FileManager.default.fileExists(atPath: Engine.weChatPath) else {
            status = nil
            errorMessage = L.err_noWeChat
            return
        }
        // 指纹取在体检之前：体检期间包若又变了，下一跳会看到不同的指纹再查一次。
        let fingerprint = AppModel.bundleFingerprint(Engine.weChatPath)
        do {
            let fresh = try await engine.doctor()
            guard generation == writeGeneration, !isBusy || duringWrite else { return }
            checkedFingerprint = fingerprint
            lastFullCheck = Date()
            let previous = status
            status = fresh
            errorMessage = lastWriteError
            await reactToChange(from: previous, to: fresh)
        } catch {
            guard generation == writeGeneration, !isBusy || duringWrite else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// 版本变了、或补丁不在了 —— 决定是自己动手还是只提醒。
    private func reactToChange(from previous: DoctorStatus?, to fresh: DoctorStatus) async {
        let knownBuild = defaults.string(forKey: Keys.lastBuild)
        if let build = fresh.build, build != knownBuild {
            defaults.set(build, forKey: Keys.lastBuild)
        }
        // 已经打上了 = 这人要这个功能，不管是谁打的。
        // 少了这一句，用命令行打过补丁再来装 GUI 的人（这个 fork 的现有用户基本都是）
        // everProtected 永远是 false，自动重打永远不触发，而且**一点声音都没有**。
        if fresh.overall == .protected || fresh.overall == .antiRevokeOnly {
            defaults.set(true, forKey: Keys.everProtected)
        }
        guard fresh.overall == .unprotected || fresh.overall == .partial else { return }
        guard autoRepatch, defaults.bool(forKey: Keys.everProtected), !isBusy, !automaticWriteBlocked else { return }

        // 够得着就自己打回去：不用密码、微信没开、补丁库认识这个版本。
        if !fresh.needsAdmin && !fresh.running && fresh.configKnown {
            let succeeded = await write(message: L.flow_resigning) { current in
                guard !current.needsAdmin else { throw EngineError.launchFailed(L.det_admin) }
                return try await self.engine.patch(variant: self.variant, admin: false)
            }
            if succeeded && (status?.overall == .protected || status?.overall == .antiRevokeOnly) {
                notify(L.notif_repatched(fresh.build ?? "?"))
            } else {
                notify(L.notif_needsYou(fresh.build ?? "?"))
            }
        } else if previous?.overall == .protected || previous?.overall == .antiRevokeOnly || knownBuild != fresh.build {
            // 够不着 —— 只说一声，绝不背着人弹授权框或强退微信。
            notify(L.notif_needsYou(fresh.build ?? "?"))
        }
    }

    // MARK: - 写动作

    /// 打补丁。微信开着就先问再退，打完原样打开回去。
    /// 防撤回与拦截自动更新由引擎各自独立执行：拦不了更新不影响防撤回，结果看体检。
    func protectNow() async {
        guard !isBusy else { return }
        guard let current = status else { return }
        if current.running {
            guard confirm(title: L.flow_wechatRunning, body: L.flow_wechatRunningBody,
                          ok: L.btn_quitWeChatAndGo) else { return }
            guard await quitWeChat() else {
                errorMessage = L.err_wechatStillRunning
                return
            }
        }
        let shouldReopen = current.running
        let succeeded = await write(message: L.flow_resigning) { fresh in
            try await self.engine.patch(variant: self.variant, admin: fresh.needsAdmin)
        }
        if succeeded && (status?.overall == .protected || status?.overall == .antiRevokeOnly) {
            defaults.set(true, forKey: Keys.everProtected)
            if shouldReopen { reopenWeChat() }
            toast = shouldReopen ? L.flow_doneProtect : nil
        }
    }

    func restoreNow() async {
        guard !isBusy else { return }
        guard let current = status else { return }
        guard confirm(title: L.flow_restoreConfirm, body: L.flow_restoreBody, ok: L.btn_restore) else { return }
        if current.running {
            guard confirm(title: L.flow_wechatRunning, body: L.flow_wechatRunningBody,
                          ok: L.btn_quitWeChatAndGo) else { return }
            guard await quitWeChat() else {
                errorMessage = L.err_wechatStillRunning
                return
            }
        }
        let shouldReopen = current.running
        let succeeded = await write(message: L.flow_resigning) { fresh in
            try await self.engine.restore(admin: fresh.needsAdmin)
        }
        if succeeded && status?.overall == .unprotected {
            defaults.set(false, forKey: Keys.everProtected)
            if shouldReopen { reopenWeChat() }
            toast = L.flow_doneRestore
        }
    }

    /// 跑一个写动作：置忙 → 执行 → 无论成败都重新体检一次。
    /// 「重新体检」不能省：失败也可能已经写了一半，界面必须显示真实状态而不是我以为的状态。
    private func write(message: String, _ body: @escaping (DoctorStatus) async throws -> String) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        writeGeneration += 1
        busyMessage = message
        lastWriteError = nil
        automaticWriteBlocked = false
        errorMessage = nil
        lastLog = ""
        var succeeded = false
        defer { isBusy = false; busyMessage = "" }
        do {
            let fresh = try await engine.doctor()
            status = fresh
            guard !fresh.running else { throw EngineError.launchFailed(L.err_wechatStillRunning) }
            lastLog = try await body(fresh)
            succeeded = true
        } catch {
            lastLog = (error as? EngineError)?.diagnosticOutput ?? error.localizedDescription
            if case EngineError.writePermissionDenied = error {
                // Do not retry a denied write on every background check. The
                // user can retry explicitly after correcting permissions.
                automaticWriteBlocked = true
            }
            lastWriteError = error.localizedDescription
            errorMessage = lastWriteError
        }
        await refresh(duringWrite: true)
        return succeeded
    }

    // MARK: - 微信进程

    private func quitWeChat() async -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: Engine.wechatBundleID)
        apps.forEach { _ = $0.terminate() }
        // 主进程退出后，辅助进程还会活几秒；引擎的 pgrep 看的是整个 Contents/MacOS/，
        // 所以这里必须等到引擎也认为它没在跑，而不是等 NSRunningApplication 变空。
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if let fresh = try? await engine.doctor(), !fresh.running {
                status = fresh
                return true
            }
        }
        return false
    }

    private func reopenWeChat() {
        let url = URL(fileURLWithPath: Engine.weChatPath)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - 杂项

    func copyReport() {
        guard let s = status else { return }
        let report = """
        WeChatUnrevoke diagnostics
        app version    : \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"))
        overall        : \(s.overall.rawValue)
        build          : \(s.build ?? "unknown")
        config known   : \(s.configKnown)  targets: \(s.configTargets.joined(separator: ", "))
        sip            : \(s.sip)
        running        : \(s.running)
        writable       : \(s.writable)
        signature      : \(s.signature)
        entitlements   : \(s.entitlementsOK ? "ok" : "STRIPPED") (\(s.entitlementKeyCount) keys)
        anti-revoke    : silent=\(s.antiRevokeSilent ?? "n/a") keeptip=\(s.antiRevokeKeeptip ?? "n/a")
        update block   : \(s.updateBlock ?? "n/a") [\(s.updateSource)]
        verdict        :
        \(s.verdict.map { "  - " + $0 }.joined(separator: "\n"))

        last engine log:
        \(lastLog.isEmpty ? "(none)" : lastLog)

        last write error:
        \(lastWriteError ?? "(none)")
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        toast = L.btn_copied
    }

    private func confirm(title: String, body: String, ok: String) -> Bool {
        if let confirmAction { return confirmAction(title, body, ok) }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: ok)
        alert.addButton(withTitle: L.btn_cancel)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            errorMessage = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private func notify(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = "WeChatUnrevoke"
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
