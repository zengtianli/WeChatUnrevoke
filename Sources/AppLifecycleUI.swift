// Shared macOS settings migration and version UI. Edit the shared source, then vendor.
#if os(macOS)
import AppKit
import CryptoKit

final class AppLifecycleUI: NSObject {
    static let shared = AppLifecycleUI()
    static let formWidth: CGFloat = 520
    /// A product's own settings groups (built with `group` and `row`), shown above the update group. Set before the
    /// window is first opened. `willShow` runs each time it opens, so the product can refresh its controls.
    var productGroups: (() -> [NSView])?
    var willShow: (() -> Void)?
    private var productName = "App"
    private var configuration: AppConfiguration?
    private var source: AppUpdateSource = .privateCloud(channel: "private")
    private var controller: NSWindowController?
    private var status = AppLifecycleUI.detailLabel()
    private var syncStatus = AppLifecycleUI.detailLabel()
    private var cloudToggle = NSSwitch()
    private var updateButton = NSButton(title: "检查更新", target: nil, action: nil)
    private var installButton = NSButton(title: "升级到新版…", target: nil, action: nil)
    private var spinner = NSProgressIndicator()
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
        willShow?()
        // A menu-bar (accessory) app is not active after its status menu closes; without this the window opens behind.
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        controller?.showWindow(nil)
        controller?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Grouped form — the look of System Settings: a caption, then a rounded card of rows with hairlines between.

    private final class Card: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            NSColor.labelColor.withAlphaComponent(0.04).setFill(); path.fill()
            NSColor.labelColor.withAlphaComponent(0.09).setStroke(); path.lineWidth = 1; path.stroke()
        }
    }
    private final class Hairline: NSView {
        override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.labelColor.withAlphaComponent(0.09).setFill()
            NSRect(x: 14, y: 0, width: max(0, bounds.width - 14), height: 1).fill()
        }
    }

    /// The small grey explanation under a row title; keep a reference to change its text later.
    static func detailLabel(_ text: String = "") -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 11); field.textColor = .secondaryLabelColor
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        return field
    }

    /// One row: title and optional explanation on the left, its control (switch, pop-up, buttons) on the right.
    static func row(_ title: String, detail: NSTextField? = nil, accessory: NSView? = nil) -> NSView {
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 13); name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let text = NSStackView(views: [name] + (detail.map { [$0] } ?? []))
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 2
        text.setHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let row = NSStackView(views: [text] + (accessory.map { [$0] } ?? []))
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 16; row.distribution = .fill
        row.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 12, right: 14)
        detail?.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
        accessory?.setContentHuggingPriority(.required, for: .horizontal)
        if let controls = accessory as? NSStackView {
            controls.setHuggingPriority(.required, for: .horizontal)
            controls.arrangedSubviews.forEach { $0.setContentHuggingPriority(.required, for: .horizontal) }
        }
        accessory?.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row
    }

    /// A card of rows under an optional caption.
    static func group(_ caption: String?, rows: [NSView]) -> NSView {
        let card = Card()
        var views: [NSView] = []
        for (index, row) in rows.enumerated() { views += index > 0 ? [Hairline(), row] : [row] }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor), stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 2), stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -2)
        ] + views.map { $0.widthAnchor.constraint(equalTo: stack.widthAnchor) })
        guard let caption else { return card }
        let label = NSTextField(labelWithString: caption)
        label.font = .systemFont(ofSize: 12, weight: .semibold); label.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [label]); heading.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 0)
        let outer = NSStackView(views: [heading, card])
        outer.orientation = .vertical; outer.alignment = .leading; outer.spacing = 6
        card.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        return outer
    }

    func checkForUpdates() {
        show()
        guard !working else { return }
        working = true
        release = nil
        installButton.isHidden = true
        updateButton.isEnabled = false
        spinner.startAnimation(nil)
        status.stringValue = "正在检查发行版本…"
        AppUpdateChecker.check(source: source, bundleID: Bundle.main.bundleIdentifier ?? "", version: currentVersion, build: currentBuild) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.working = false
                self.updateButton.isEnabled = true
                self.spinner.stopAnimation(nil)
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.formWidth + 40, height: 240),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: true)
        window.title = "\(productName) 设置"
        window.isReleasedWhenClosed = false
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        let name = NSTextField(labelWithString: productName)
        name.font = .systemFont(ofSize: 17, weight: .semibold)
        let version = NSTextField(labelWithString: "版本 \(currentVersion) (\(currentBuild))")
        version.font = .systemFont(ofSize: 12); version.textColor = .secondaryLabelColor
        let titles = NSStackView(views: [name, version])
        titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 2
        let header = NSStackView(views: [icon, titles])
        header.spacing = 12; header.alignment = .centerY; header.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 2, right: 0)
        status.stringValue = "按需检查新版，不在后台轮询。"
        updateButton.target = self; updateButton.action = #selector(checkUpdates)
        installButton.target = self; installButton.action = #selector(upgrade)
        installButton.isHidden = true; installButton.keyEquivalent = "\r"
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        var groups: [NSView] = productGroups?() ?? []
        if configuration?.hasSettings == true {
            cloudToggle.target = self; cloudToggle.action = #selector(toggleCloud)
            let export = NSButton(title: "导出配置…", target: self, action: #selector(exportConfiguration))
            let `import` = NSButton(title: "导入配置…", target: self, action: #selector(importConfiguration))
            let transfers = NSStackView(views: [export, `import`]); transfers.spacing = 8
            groups.append(Self.group("配置", rows: [
                Self.row("使用 iCloud 记住配置", detail: Self.detailLabel("沿用系统 Apple ID；开启后自动记住设置，换机时恢复。权限和凭证保留在本机。"), accessory: cloudToggle),
                Self.row("导入与导出", detail: syncStatus, accessory: transfers)]))
        }
        let actions = NSStackView(views: [spinner, updateButton, installButton]); actions.spacing = 8
        groups.append(Self.group("软件更新", rows: [Self.row("当前版本 \(currentVersion) (\(currentBuild))", detail: status, accessory: actions)]))
        let stack = NSStackView(views: [header] + groups)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalToConstant: Self.formWidth),
            icon.widthAnchor.constraint(equalToConstant: 48), icon.heightAnchor.constraint(equalToConstant: 48)
        ] + groups.map { $0.widthAnchor.constraint(equalTo: stack.widthAnchor) })
        content.layoutSubtreeIfNeeded()
        window.setContentSize(content.fittingSize)
        window.center()
        controller = NSWindowController(window: window)
        refreshConfiguration()
    }

    private func refreshConfiguration() {
        cloudToggle.state = configuration?.enabled == true ? .on : .off
        syncStatus.stringValue = configuration?.status ?? ""
    }

    /// Same window construction as the user-facing action; never orders a window in.
    func offscreenSnapshot(to url: URL, appearance: NSAppearance.Name = .aqua) throws -> [String: Bool] {
        guard NSApp.activationPolicy() == .prohibited else { throw AppUpdateError("离屏验收必须禁止显示窗口和 Dock 图标。") }
        makeWindow()
        willShow?()
        guard let window = controller?.window, let view = window.contentView else { throw AppUpdateError("窗口构造失败。") }
        window.appearance = NSAppearance(named: appearance)
        view.layoutSubtreeIfNeeded()
        window.setContentSize(view.fittingSize)
        view.layoutSubtreeIfNeeded()
        // Retina-sized, on the window background the real window has (the content view itself draws none).
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw AppUpdateError("无法渲染设置窗口。") }
        bitmap.size = view.bounds.size
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw AppUpdateError("无法渲染设置窗口。") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        window.effectiveAppearance.performAsCurrentDrawingAppearance { NSColor.windowBackgroundColor.setFill(); view.bounds.fill() }
        NSGraphicsContext.restoreGraphicsState()
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
            self.spinner.startAnimation(nil)
            self.status.stringValue = "正在下载并验证新版…"
            AppUpgradeInstaller.prepare(release: release, currentBundle: Bundle.main.bundleURL) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .failure(let error):
                        self.working = false; self.updateButton.isEnabled = true; self.installButton.isEnabled = true
                        self.spinner.stopAnimation(nil)
                        self.status.stringValue = "升级未完成，当前 App 已保留：" + error.localizedDescription
                    case .success(let prepared):
                        do {
                            try AppUpgradeInstaller.launchReplacement(prepared, currentBundle: Bundle.main.bundleURL,
                                                                       pid: ProcessInfo.processInfo.processIdentifier)
                            NSApp.terminate(nil)
                        } catch {
                            self.working = false; self.updateButton.isEnabled = true; self.installButton.isEnabled = true
                            self.spinner.stopAnimation(nil)
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

    /// The window passes its own pid and quits; the helper waits for that process, swaps the bundle and reopens the app.
    /// The command line (`update install`) quits the running app itself first, passes pid 0 (nothing to wait for), waits
    /// for the returned process and reads its exit status; `relaunch: false` leaves an app that was not running closed.
    /// `backup` is the temporary rollback location (removed to Trash after verification; retained on failure).
    /// `reopens` is whether the helper was told to open the app again (never in an isolated run).
    @discardableResult
    static func launchReplacement(_ prepared: Prepared, currentBundle: URL, pid: Int32, relaunch: Bool = true) throws -> (process: Process, backup: URL?, reopens: Bool) {
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
            try process.run(); try handle.close(); return (process, nil, true)
        }
        if let recipe = prepared.installation, recipe != "bundle" { throw AppUpdateError("此产品需要其专用安装事务：" + recipe) }
        guard let info = NSDictionary(contentsOf: prepared.app.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              let identifier = info["CFBundleIdentifier"] as? String,
              let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String,
              identifier == Bundle(url: currentBundle)?.bundleIdentifier,
              !((try? currentBundle.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? true) else {
            throw AppUpdateError("替换前 App 身份或路径不匹配。")
        }
        // No user input, permissions, defaults or support directories are touched by this helper.
        let script = prepared.directory.appendingPathComponent("replace.sh")
        let body = """
        #!/bin/bash
        set -euo pipefail
        app_pid="$1"; source_app="$2"; target_app="$3"; task_dir="$4"; backup_app="$5"; relaunch="$6"
        expected_id="$7"; expected_version="$8"; expected_build="$9"; trash_dir="${10}"
        same_product() {
          [ ! -L "$1" ] && [ -d "$1" ] &&
            [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist")" = "$expected_id" ]
        }
        verified_new() {
          same_product "$target_app" &&
            /usr/bin/codesign --verify --deep --strict "$target_app" &&
            [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$target_app/Contents/Info.plist")" = "$expected_version" ] &&
            [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$target_app/Contents/Info.plist")" = "$expected_build" ]
        }
        retire_old() {
          local old="$1" name="$2"
          same_product "$old" || return 1
          /bin/mkdir -p "$trash_dir" || return 1
          [ "$(/usr/bin/stat -f %d "$old")" = "$(/usr/bin/stat -f %d "$trash_dir")" ] || return 1
          /bin/mv "$old" "$trash_dir/$name"
        }
        if [ "$app_pid" != 0 ]; then
          for ((attempt=0;attempt<120;attempt++)); do
            if ! kill -0 "$app_pid" 2>/dev/null; then break; fi
            sleep 0.5
          done
          if kill -0 "$app_pid" 2>/dev/null; then exit 1; fi
        fi
        next_app="${target_app%.app}.upgrade-$app_pid.app"
        /bin/mkdir -p "$(/usr/bin/dirname "$backup_app")"
        /usr/bin/ditto "$source_app" "$next_app"
        /usr/bin/codesign --verify --deep --strict "$next_app"
        same_product "$target_app"
        if [ -e "$backup_app" ] || [ -L "$backup_app" ]; then
          same_product "$backup_app"
          /bin/mv "$backup_app" "$task_dir/previous-backup.app"
        fi
        /bin/mv "$target_app" "$backup_app"
        if ! /bin/mv "$next_app" "$target_app"; then /bin/mv "$backup_app" "$target_app"; exit 1; fi
        started=1
        if ! verified_new; then started=0; fi
        if [ "$started" = 1 ] && [ "$relaunch" = 1 ]; then
          if ! /usr/bin/open -g -j "$target_app"; then started=0; else
            started=0
            for ((attempt=0;attempt<40;attempt++)); do
              while IFS= read -r running; do
                case "$running" in "$target_app"/Contents/MacOS/*) started=1; break;; esac
              done < <(/bin/ps -axo comm=)
              [ "$started" = 1 ] && break
              sleep 0.25
            done
          fi
        fi
        if [ "$started" != 1 ]; then
          /bin/mv "$target_app" "$task_dir/failed-new.app"
          /bin/mv "$backup_app" "$target_app"
          if [ "$relaunch" = 1 ]; then /usr/bin/open -g -j "$target_app"; fi
          exit 1
        fi
        if ! retire_old "$backup_app" "${target_app##*/}"; then
          echo "cleanup_failed: installed app verified; old app retained at $backup_app" >&2
          exit 2
        fi
        if [ -e "$task_dir/previous-backup.app" ] && ! retire_old "$task_dir/previous-backup.app" "previous-${target_app##*/}"; then
          echo "cleanup_failed: previous old app retained at $task_dir/previous-backup.app" >&2
          exit 2
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
        let backup = actualBackups.appendingPathComponent(currentBundle.lastPathComponent)
        let trash = (noRelaunch ? URL(fileURLWithPath: environment["APP_LIFECYCLE_SUPPORT_DIR"]!).appendingPathComponent("trash")
                     : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
            .appendingPathComponent(prepared.directory.lastPathComponent, isDirectory: true)
        let reopens = relaunch && !noRelaunch
        process.arguments = [script.path, String(pid), prepared.app.path, currentBundle.path, prepared.directory.path,
                             backup.path, reopens ? "1" : "0", identifier, version, build, trash.path]
        let log = prepared.directory.appendingPathComponent("install.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log); process.standardOutput = handle; process.standardError = handle
        try process.run(); try handle.close()
        return (process, backup, reopens)
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
