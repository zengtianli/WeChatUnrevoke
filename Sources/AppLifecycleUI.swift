// Shared macOS settings migration and version UI. Edit the shared source, then vendor.
#if os(macOS)
import AppKit
import CryptoKit

final class AppLifecycleUI: NSObject {
    static let shared = AppLifecycleUI()
    private var productName = "App"
    private var configuration: AppConfiguration?
    private var source: AppUpdateSource = .privateCloud(channel: "private")
    private var controller: NSWindowController?
    private var status = NSTextField(wrappingLabelWithString: "")
    private var syncStatus = NSTextField(wrappingLabelWithString: "")
    private var cloudToggle = NSButton(checkboxWithTitle: "使用 iCloud 记住配置", target: nil, action: nil)
    private var updateButton = NSButton(title: "检查更新", target: nil, action: nil)
    private var installButton = NSButton(title: "升级到新版…", target: nil, action: nil)
    private var release: AppRelease?
    private var observers: [NSObjectProtocol] = []
    private var working = false
    private var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    private var currentBuild: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }

    static func install(name: String, configuration: AppConfiguration?, updateSource: AppUpdateSource) {
        let instance = shared
        instance.productName = name
        instance.configuration = configuration
        instance.source = updateSource
        configuration?.start()
        if instance.observers.isEmpty {
            instance.observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
                DispatchQueue.main.async { shared.attachMenu() }
            })
            instance.observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in shared.attachMenu() })
            instance.observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name("AppConfigurationStatusChanged"), object: configuration, queue: .main) { _ in shared.refreshConfiguration() })
        }
        instance.attachMenu()
    }

    static func menuItems() -> [NSMenuItem] {
        let settings = NSMenuItem(title: "配置与更新…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = shared
        let update = NSMenuItem(title: "检查更新…", action: #selector(checkUpdates), keyEquivalent: "")
        update.target = shared
        return [settings, update]
    }

    private func attachMenu() {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu,
              !appMenu.items.contains(where: { ($0.target === self && $0.action == #selector(openSettings)) || $0.title == "配置与更新…" }) else { return }
        let items = Self.menuItems()
        let index = min(1, appMenu.numberOfItems)
        for (offset, item) in items.enumerated() { appMenu.insertItem(item, at: index + offset) }
        appMenu.insertItem(.separator(), at: index + items.count)
    }

    @objc private func openSettings() { show() }
    @objc private func checkUpdates() { checkForUpdates() }

    func show() {
        makeWindow()
        refreshConfiguration()
        controller?.showWindow(nil)
        controller?.window?.makeKeyAndOrderFront(nil)
    }

    func checkForUpdates() {
        show()
        guard !working else { return }
        working = true
        release = nil
        installButton.isHidden = true
        updateButton.isEnabled = false
        status.stringValue = "正在检查发行版本…"
        AppUpdateChecker.check(source: source, bundleID: Bundle.main.bundleIdentifier ?? "", version: currentVersion, build: currentBuild) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.working = false
                self.updateButton.isEnabled = true
                switch result {
                case .failure(let error): self.status.stringValue = "检查未完成：" + error.localizedDescription
                case .success(let release):
                    self.release = release
                    if release.isNewer(than: self.currentVersion, build: self.currentBuild) {
                        self.status.stringValue = "有新版 \(release.version) (\(release.build))，当前 \(self.currentVersion) (\(self.currentBuild))。升级会保留本机配置。"
                        self.installButton.isHidden = release.downloadURL == nil
                        self.installButton.title = AppUpgradeInstaller.supportsReplacement(release: release, currentBundle: Bundle.main.bundleURL) ? "升级到新版…" : "下载新版…"
                    } else if AppVersion.compare(self.currentVersion, release.version) == .orderedDescending {
                        self.status.stringValue = "当前 \(self.currentVersion) (\(self.currentBuild))；此渠道正式发行版本为 \(release.version) (\(release.build))。"
                    } else { self.status.stringValue = "当前已是此渠道最新版：\(self.currentVersion) (\(self.currentBuild))。" }
                }
            }
        }
    }

    private func makeWindow() {
        guard controller == nil else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 510, height: configuration?.hasSettings == true ? 355 : 230),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: true)
        window.title = "\(productName) · 配置与更新"
        window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: productName + "  " + currentVersion + " (" + currentBuild + ")")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        status.stringValue = "按需检查新版，不增加后台轮询。"
        status.font = .systemFont(ofSize: 12)
        updateButton.target = self; updateButton.action = #selector(checkUpdates)
        installButton.target = self; installButton.action = #selector(upgrade)
        installButton.isHidden = true
        var views: [NSView] = [title]
        if configuration?.hasSettings == true {
            cloudToggle.target = self; cloudToggle.action = #selector(toggleCloud)
            syncStatus.font = .systemFont(ofSize: 12)
            syncStatus.textColor = .secondaryLabelColor
            let note = NSTextField(wrappingLabelWithString: "沿用系统 Apple ID；开启后自动记住设置，换机时恢复。权限和凭证保留在本机。")
            note.font = .systemFont(ofSize: 12); note.textColor = .secondaryLabelColor
            let export = NSButton(title: "导出配置…", target: self, action: #selector(exportConfiguration))
            let `import` = NSButton(title: "导入配置…", target: self, action: #selector(importConfiguration))
            let transfers = NSStackView(views: [export, `import`])
            transfers.spacing = 10
            views += [cloudToggle, note, syncStatus, transfers]
        }
        let actions = NSStackView(views: [updateButton, installButton]); actions.spacing = 10
        views += [status, actions]
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -24)
        ])
        for view in views where view is NSTextField { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        controller = NSWindowController(window: window)
        refreshConfiguration()
    }

    private func refreshConfiguration() {
        cloudToggle.state = configuration?.enabled == true ? .on : .off
        syncStatus.stringValue = configuration?.status ?? ""
    }

    /// Same window construction as the user-facing action; never orders a window in.
    func offscreenSnapshot(to url: URL) throws -> [String: Bool] {
        guard NSApp.activationPolicy() == .prohibited else { throw AppUpdateError("离屏验收必须禁止显示窗口和 Dock 图标。") }
        makeWindow()
        guard let window = controller?.window, let view = window.contentView else { throw AppUpdateError("窗口构造失败。") }
        window.appearance = NSAppearance(named: .aqua)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw AppUpdateError("无法渲染设置窗口。") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw AppUpdateError("无法导出窗口截图。") }
        try data.write(to: url, options: .atomic)
        return ["upgrade_window_offscreen": !window.isVisible && !window.isKeyWindow,
                "upgrade_native_titlebar": window.styleMask.contains(.titled) && window.styleMask.contains(.closable),
                "upgrade_actual_button_target": updateButton.target === self && updateButton.action == #selector(checkUpdates),
                "upgrade_image_rendered": data.count > 1_000 && bitmap.pixelsWide >= 400]
    }
    @objc private func toggleCloud() {
        configuration?.setEnabled(cloudToggle.state == .on)
        refreshConfiguration()
    }
    @objc private func exportConfiguration() {
        guard let configuration else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = productName + "-config.json"
        panel.beginSheetModal(for: controller!.window!) { response in
            guard response == .OK, let url = panel.url else { return }
            do { try configuration.exportData().write(to: url, options: .atomic); self.syncStatus.stringValue = "配置已导出。" }
            catch { self.syncStatus.stringValue = "导出未完成：" + error.localizedDescription }
        }
    }
    @objc private func importConfiguration() {
        guard let configuration else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.beginSheetModal(for: controller!.window!) { response in
            guard response == .OK, let url = panel.url else { return }
            do { try configuration.importData(Data(contentsOf: url)); self.syncStatus.stringValue = "已导入；原配置已备份。" }
            catch { self.syncStatus.stringValue = "导入未完成：" + error.localizedDescription }
        }
    }

    @objc private func upgrade() {
        guard !working, let release, let url = release.downloadURL else { return }
        if !AppUpgradeInstaller.supportsReplacement(release: release, currentBundle: Bundle.main.bundleURL) {
            NSWorkspace.shared.open(url)
            status.stringValue = "已打开正式安装包下载；安装新版会保留支持目录中的配置。"
            return
        }
        let alert = NSAlert()
        alert.messageText = "升级 \(productName) 到 \(release.version)？"
        alert.informativeText = "将验证发行包和 App 签名，然后替换当前 App 并重新打开。配置保留；替换失败可回滚。"
        alert.addButton(withTitle: "升级"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: controller!.window!) { answer in
            guard answer == .alertFirstButtonReturn else { return }
            self.working = true; self.updateButton.isEnabled = false; self.installButton.isEnabled = false
            self.status.stringValue = "正在下载并验证新版…"
            AppUpgradeInstaller.prepare(release: release, currentBundle: Bundle.main.bundleURL) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .failure(let error):
                        self.working = false; self.updateButton.isEnabled = true; self.installButton.isEnabled = true
                        self.status.stringValue = "升级未完成，当前 App 已保留：" + error.localizedDescription
                    case .success(let prepared):
                        do {
                            try AppUpgradeInstaller.launchReplacement(prepared, currentBundle: Bundle.main.bundleURL,
                                                                       pid: ProcessInfo.processInfo.processIdentifier)
                            NSApp.terminate(nil)
                        } catch {
                            self.working = false; self.updateButton.isEnabled = true; self.installButton.isEnabled = true
                            self.status.stringValue = "无法替换 App，当前 App 已保留：" + error.localizedDescription
                        }
                    }
                }
            }
        }
    }
}

enum AppUpgradeInstaller {
    struct Prepared { let app: URL; let directory: URL; let installation: String? }

    static func supportsReplacement(release: AppRelease, currentBundle: URL) -> Bool {
        guard release.sha256 != nil, let url = release.downloadURL, currentBundle.pathExtension == "app",
              FileManager.default.isWritableFile(atPath: currentBundle.deletingLastPathComponent().path) else { return false }
        // A publicly downloaded bundle needs the existing developer identity.
        // Ad-hoc products retain their actual download-and-install distribution flow.
        return url.isFileURL || (try? signingTeam(currentBundle)) != nil
    }

    static func prepare(release: AppRelease, currentBundle: URL, completion: @escaping (Result<Prepared, Error>) -> Void) {
        guard let url = release.downloadURL, let expectedHash = release.sha256,
              expectedHash.count == 64, expectedHash.allSatisfy(\.isHexDigit) else {
            completion(.failure(AppUpdateError("发行包缺少完整性校验。"))); return
        }
        func verify(_ archive: URL, directory: URL) {
            DispatchQueue.global(qos: .utility).async {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: archive.path)
                    let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                    guard size > 0, size <= 1_500_000_000, release.size == nil || release.size == size else { throw AppUpdateError("发行包大小不匹配。") }
                    let file = try FileHandle(forReadingFrom: archive); defer { try? file.close() }
                    var hasher = SHA256()
                    while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hasher.update(data: data) }
                    let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                    guard hash == expectedHash.lowercased() else { throw AppUpdateError("发行包 SHA256 校验失败。") }
                    let extracted = directory.appendingPathComponent("payload", isDirectory: true)
                    try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
                    if url.pathExtension.lowercased() == "zip" {
                        _ = try command("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
                    } else if url.pathExtension.lowercased() == "dmg" {
                        let mount = directory.appendingPathComponent("mount", isDirectory: true)
                        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
                        _ = try command("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-quiet", "-mountpoint", mount.path, archive.path])
                        defer { _ = try? command("/usr/bin/hdiutil", ["detach", "-quiet", mount.path]) }
                        let apps = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
                        guard apps.count == 1 else { throw AppUpdateError("安装包中没有唯一的 App。") }
                        _ = try command("/usr/bin/ditto", [apps[0].path, extracted.appendingPathComponent(apps[0].lastPathComponent).path])
                    } else { throw AppUpdateError("不支持此安装包格式。") }
                    let apps = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
                    guard apps.count == 1, let bundle = Bundle(url: apps[0]), let old = Bundle(url: currentBundle),
                          bundle.bundleIdentifier == old.bundleIdentifier,
                          bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == release.version,
                          release.build == "0" || bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String == release.build else {
                        throw AppUpdateError("安装包 App 身份或版本不匹配。")
                    }
                    _ = try command("/usr/bin/codesign", ["--verify", "--deep", "--strict", apps[0].path])
                    let oldTeam = try signingTeam(currentBundle), newTeam = try signingTeam(apps[0])
                    if !url.isFileURL && oldTeam == nil { throw AppUpdateError("当前 App 无开发者身份，请使用正式下载渠道手动安装。") }
                    guard oldTeam == newTeam else { throw AppUpdateError("新版的签名开发者与当前 App 不同。") }
                    if !url.isFileURL { _ = try command("/usr/sbin/spctl", ["--assess", "--type", "execute", apps[0].path]) }
                    if let minimum = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String {
                        let system = ProcessInfo.processInfo.operatingSystemVersion
                        let current = "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
                        guard AppVersion.compare(minimum, current) != .orderedDescending else { throw AppUpdateError("新版需要 macOS " + minimum + " 或更新系统。") }
                    }
                    completion(.success(Prepared(app: apps[0], directory: directory, installation: release.installation)))
                } catch {
                    try? FileManager.default.removeItem(at: directory)
                    completion(.failure(error))
                }
            }
        }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("app-upgrade-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let archive = directory.appendingPathComponent("archive." + url.pathExtension)
            if url.isFileURL {
                DispatchQueue.global(qos: .utility).async {
                    do {
                        if FileManager.default.isUbiquitousItem(at: url) { try FileManager.default.startDownloadingUbiquitousItem(at: url) }
                        var error: NSError?, copyError: Error?
                        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { coordinated in
                            do { try FileManager.default.copyItem(at: coordinated, to: archive) } catch { copyError = error }
                        }
                        if let error { throw error }; if let copyError { throw copyError }
                        verify(archive, directory: directory)
                    } catch { try? FileManager.default.removeItem(at: directory); completion(.failure(error)) }
                }
            } else {
                #if APP_LIFECYCLE_LOCAL_ONLY
                throw AppUpdateError("此 App 只安装 iCloud 已下载到本机的私有发行包。")
                #else
                guard url.scheme == "https" else { throw AppUpdateError("下载来源必须使用 HTTPS。") }
                let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForResource = 300
                let session = URLSession(configuration: configuration)
                var request = URLRequest(url: url); request.setValue("TianliApp-Update/1.0", forHTTPHeaderField: "User-Agent")
                session.downloadTask(with: request) { temporary, response, error in
                    defer { session.finishTasksAndInvalidate() }
                    do {
                        if let error { throw error }
                        guard let temporary, let http = response as? HTTPURLResponse, http.statusCode == 200, http.url?.scheme == "https" else { throw AppUpdateError("下载未完成。") }
                        try FileManager.default.moveItem(at: temporary, to: archive)
                        verify(archive, directory: directory)
                    } catch { try? FileManager.default.removeItem(at: directory); completion(.failure(error)) }
                }.resume()
                #endif
            }
        } catch { completion(.failure(error)) }
    }

    static func launchReplacement(_ prepared: Prepared, currentBundle: URL, pid: Int32) throws {
        guard FileManager.default.isWritableFile(atPath: currentBundle.deletingLastPathComponent().path),
              currentBundle.pathExtension == "app" else { throw AppUpdateError("当前安装目录不可写，请把 App 安装在用户可写的位置。") }
        if prepared.installation == "notifhub-collector" {
            guard let bundle = Bundle(url: prepared.app),
                  bundle.bundleIdentifier == "cyou.tianli.notifhubbar",
                  bundle.object(forInfoDictionaryKey: "NotihubCollectorUpdateAPI") as? Int == 1,
                  let executable = bundle.executableURL else { throw AppUpdateError("此 Notihub 发行包缺少安全采集器升级接口。") }
            let process = Process(); process.executableURL = executable
            process.arguments = ["--collector-update", "install", "--app", prepared.app.path,
                                 "--target", currentBundle.path, "--parent-pid", String(pid),
                                 "--task-dir", prepared.directory.path]
            let log = prepared.directory.appendingPathComponent("install.log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let handle = try FileHandle(forWritingTo: log); process.standardOutput = handle; process.standardError = handle
            try process.run(); try handle.close(); return
        }
        if let recipe = prepared.installation, recipe != "bundle" { throw AppUpdateError("此产品需要其专用安装事务：" + recipe) }
        // No user input, permissions, defaults or support directories are touched by this helper.
        let script = prepared.directory.appendingPathComponent("replace.sh")
        let body = """
        #!/bin/bash
        set -euo pipefail
        app_pid="$1"; source_app="$2"; target_app="$3"; task_dir="$4"; backup_app="$5"; relaunch="$6"
        for ((attempt=0;attempt<120;attempt++)); do
          if ! kill -0 "$app_pid" 2>/dev/null; then break; fi
          sleep 0.5
        done
        if kill -0 "$app_pid" 2>/dev/null; then exit 1; fi
        next_app="${target_app%.app}.upgrade-$app_pid.app"
        /bin/mkdir -p "$(/usr/bin/dirname "$backup_app")"
        /usr/bin/ditto "$source_app" "$next_app"
        /usr/bin/codesign --verify --deep --strict "$next_app"
        if [ -e "$backup_app" ]; then /bin/mv "$backup_app" "$task_dir/previous-backup.app"; fi
        /bin/mv "$target_app" "$backup_app"
        if ! /bin/mv "$next_app" "$target_app"; then /bin/mv "$backup_app" "$target_app"; exit 1; fi
        if [ "$relaunch" = 1 ] && ! /usr/bin/open -g -j "$target_app"; then
          /bin/mv "$target_app" "$task_dir/failed-new.app"
          /bin/mv "$backup_app" "$target_app"
          /usr/bin/open -g -j "$target_app"
          exit 1
        fi
        /bin/rm -rf "$task_dir"
        """
        try Data(body.utf8).write(to: script, options: .atomic)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash")
        let backups = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TianliApps/UpgradeBackups/" + (Bundle(url: currentBundle)?.bundleIdentifier ?? "App"), isDirectory: true)
        let environment = ProcessInfo.processInfo.environment
        let isolatedRoot = environment["APP_LIFECYCLE_SUPPORT_DIR"].map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path + "/" }
        let noRelaunch = environment["APP_LIFECYCLE_NO_RELAUNCH"] == "1" && isolatedRoot.map { currentBundle.resolvingSymlinksInPath().path.hasPrefix($0) } == true
        let actualBackups = noRelaunch ? URL(fileURLWithPath: environment["APP_LIFECYCLE_SUPPORT_DIR"]!).appendingPathComponent("backups") : backups
        process.arguments = [script.path, String(pid), prepared.app.path, currentBundle.path, prepared.directory.path,
                             actualBackups.appendingPathComponent(currentBundle.lastPathComponent).path, noRelaunch ? "0" : "1"]
        let log = prepared.directory.appendingPathComponent("install.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log); process.standardOutput = handle; process.standardError = handle
        try process.run(); try handle.close()
    }

    private static func signingTeam(_ app: URL) throws -> String? {
        let value = try command("/usr/bin/codesign", ["-dv", "--verbose=4", app.path])
        return value.split(separator: "\n").first(where: { $0.hasPrefix("TeamIdentifier=") })
            .map { String($0.dropFirst("TeamIdentifier=".count)) }.flatMap { $0 == "not set" ? nil : $0 }
    }
    @discardableResult private static func command(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw AppUpdateError("安装包验证失败：" + String(decoding: output.prefix(4096), as: UTF8.self)) }
        return String(decoding: output, as: UTF8.self)
    }
}
#endif
