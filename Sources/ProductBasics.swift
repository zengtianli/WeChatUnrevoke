import AppKit
import Foundation

// App entry only; the shared product configuration factory also compiles into
// the companion CLI without requiring GUI controls or the app entry point.
extension ProductLifecycle {
    @MainActor
    static func commandMode(_ words: [String]) -> Int32? {
        if AppLifecycleCLI.handles(words.first) {
            return AppLifecycleCLI.run(words, product: .init(command: "WeChatUnrevoke", name: name,
                configuration: makeConfiguration(), updateSource: updateSource()))
        }
        return ProductSettings.commandMode(words)
    }
}

/// Product controls use the same preference domain and allowlist as the window,
/// configuration transfer and command readback. No patch is performed here.
@MainActor
final class ProductSettings: NSObject {
    static private(set) var current: ProductSettings?
    let defaults: UserDefaults
    let shortcuts: AppShortcuts
    let variant = NSPopUpButton()
    let autoRepatch = NSSwitch()
    let shortcutEnabled = NSSwitch()
    let shortcutChoice = NSPopUpButton()
    let shortcutStatus = AppLifecycleUI.detailLabel()
    let choices: [AppShortcuts.Binding] = [
        .init(key: "r", modifiers: .command),
        .init(key: "r", modifiers: [.command, .shift]),
        .init(key: "r", modifiers: [.command, .option])]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        shortcuts = AppShortcuts(defaults: defaults) {
            NotificationCenter.default.post(name: .consoleRefresh, object: nil)
        }
        super.init()
        variant.addItems(withTitles: [L.t("保留提示", "Keep recall notice"), L.t("静默", "Silent")])
        variant.itemArray[0].representedObject = "keeptip"
        variant.itemArray[1].representedObject = "silent"
        shortcutChoice.addItems(withTitles: ["⌘R", "⇧⌘R", "⌥⌘R"])
        for control in [variant, autoRepatch, shortcutEnabled, shortcutChoice] as [NSControl] {
            control.target = self; control.action = #selector(changed(_:))
        }
        refresh()
    }

    static func install(configuration: AppConfiguration) {
        let settings = ProductSettings(defaults: ProductLifecycle.preferences())
        current = settings
        configuration.onChange = {
            settings.refresh()
            NotificationCenter.default.post(name: .unrevokePreferencesChanged, object: nil)
        }
        AppLifecycleUI.shared.productGroups = { settings.groups() }
        AppLifecycleUI.shared.willShow = { settings.shortcuts.installMenu(); settings.refresh() }
        settings.shortcuts.installMenu()
        settings.refresh()
    }

    func refresh() {
        let value = defaults.string(forKey: "variant") ?? "keeptip"
        variant.selectItem(at: value == "silent" ? 1 : 0)
        autoRepatch.state = defaults.object(forKey: "autoRepatch") as? Bool ?? true ? .on : .off
        shortcuts.refresh()
        shortcuts.menuItem?.title = L.btn_recheck
        shortcutEnabled.state = shortcuts.enabled ? .on : .off
        if let index = choices.firstIndex(where: { $0.key == shortcuts.binding.key && $0.modifiers == shortcuts.binding.modifiers }) {
            shortcutChoice.selectItem(at: index)
        } else { shortcutChoice.select(nil) }
        shortcutStatus.stringValue = shortcuts.descriptionText
    }

    @objc func changed(_ sender: NSControl) {
        do {
            switch sender {
            case variant: defaults.set(variant.selectedItem?.representedObject as? String, forKey: "variant")
            case autoRepatch: defaults.set(autoRepatch.state == .on, forKey: "autoRepatch")
            case shortcutEnabled: shortcuts.setEnabled(shortcutEnabled.state == .on)
            case shortcutChoice:
                guard choices.indices.contains(shortcutChoice.indexOfSelectedItem) else { return }
                try shortcuts.setBinding(choices[shortcutChoice.indexOfSelectedItem])
            default: return
            }
            defaults.synchronize(); refresh()
            NotificationCenter.default.post(name: .unrevokePreferencesChanged, object: nil)
        } catch { refresh(); shortcutStatus.stringValue = error.localizedDescription }
    }

    func groups() -> [NSView] {
        [AppLifecycleUI.group(L.t("微信保护偏好", "Protection preferences"), rows: [
            AppLifecycleUI.row(L.t("防撤回方式", "Recall notice"), accessory: variant),
            AppLifecycleUI.row(L.t("更新后自动重打", "Reapply after updates"),
                detail: AppLifecycleUI.detailLabel(L.t("仍须无需密码、微信已退出、曾成功保护；恢复偏好不授权写微信。", "Requires no password, WeChat closed and prior protection. Restoring settings does not authorize patching.")), accessory: autoRepatch)]),
         AppLifecycleUI.group(L.t("应用快捷键", "Application shortcuts"), rows: [
            AppLifecycleUI.row(L.t("启用重新检查快捷键", "Enable refresh shortcut"), detail: shortcutStatus, accessory: shortcutEnabled),
            AppLifecycleUI.row(L.t("按键组合", "Key binding"),
                detail: AppLifecycleUI.detailLabel(L.t("只在本 App 内生效；系统/编辑组合和已有菜单冲突会拒绝，关闭后保留组合。", "Applies within this app. Reserved and conflicting menu bindings are rejected; disabling retains the binding.")), accessory: shortcutChoice)])]
    }

    static func commandMode(_ words: [String]) -> Int32? {
        guard let verb = words.first, ["settings", "shortcuts"].contains(verb) else { return nil }
        let defaults = ProductLifecycle.preferences()
        let shortcuts = AppShortcuts(defaults: defaults, action: {})
        var code: Int32 = 0
        var body: [String: Any]
        var tail = Array(words.dropFirst())
        let action = tail.first.map { !$0.hasPrefix("--") } == true ? tail.removeFirst() : "status"
        let validFlags = tail.allSatisfy { ["--yes", "--json"].contains($0) } && Set(tail).count == tail.count
        let validAction = verb == "settings" ? action == "status" : ["status", "on", "off"].contains(action)
        if !validFlags || !validAction { code = 2 }
        else if verb == "shortcuts" && ["on", "off"].contains(action) && tail.contains("--yes") {
            shortcuts.setEnabled(action == "on")
        } else if action != "status" {
            code = 2
        }
        if verb == "settings" {
            body = ["variant": defaults.string(forKey: "variant") ?? "keeptip",
                    "auto_repatch": defaults.object(forKey: "autoRepatch") as? Bool ?? true]
        } else {
            body = ["enabled": shortcuts.enabled, "key": shortcuts.binding.key,
                    "modifiers": shortcuts.binding.modifiers.rawValue, "scope": "application_menu"]
        }
        body["ok"] = code == 0
        if code != 0 { body["error"] = "Usage: settings status | shortcuts status|on|off [--yes] [--json]" }
        if let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) {
            print(String(decoding: data, as: UTF8.self))
        }
        return code
    }
}

/// Runs inside the real compiled app. Controls invoke production selectors;
/// the renderer constructs the ordinary settings window without ordering it in.
@MainActor
enum ProductBasicsSelfTest {
    static func launch() {
        guard ProcessInfo.processInfo.environment["APP_LIFECYCLE_SUPPORT_DIR"] != nil,
              let output = ProcessInfo.processInfo.environment["UNREVOKE_BASICS_OUT"] else { exit(78) }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let root = NSMenu()
        let item = NSMenuItem(); item.submenu = NSMenu(title: "WeChatUnrevoke"); root.addItem(item)
        app.mainMenu = root
        let config = ProductLifecycle.makeConfiguration()
        ProductSettings.install(configuration: config)
        AppLifecycleUI.install(name: ProductLifecycle.name, configuration: config,
                               updateSource: ProductLifecycle.updateSource(), startConfiguration: false)
        var checks: [String: Bool] = [:]
        do {
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let settings = ProductSettings.current!
            checks["settings.shortcut_migration_schema"] = Set(AppShortcuts.portableKeys).isSubset(of: Set(ProductLifecycle.portableKeys))
            func act(_ control: NSControl) { _ = app.sendAction(control.action!, to: control.target, from: control) }
            settings.variant.selectItem(at: 1); act(settings.variant)
            settings.autoRepatch.state = .off; act(settings.autoRepatch)
            checks["settings.real_control_actions"] = settings.defaults.string(forKey: "variant") == "silent" && !settings.defaults.bool(forKey: "autoRepatch")
            settings.shortcutChoice.selectItem(at: 1); act(settings.shortcutChoice)
            var refreshes = 0
            let observer = NotificationCenter.default.addObserver(forName: .consoleRefresh, object: nil, queue: nil) { _ in refreshes += 1 }
            defer { NotificationCenter.default.removeObserver(observer) }
            let shortcutItem = settings.shortcuts.menuItem!
            _ = app.sendAction(shortcutItem.action!, to: shortcutItem.target, from: shortcutItem)
            checks["shortcuts.real_refresh_action"] = refreshes == 1 && shortcutItem.keyEquivalent == "r" && shortcutItem.keyEquivalentModifierMask.contains(.shift)
            settings.shortcutEnabled.state = .off; act(settings.shortcutEnabled)
            let retained = settings.defaults.dictionary(forKey: AppShortcuts.bindingKey)
            let disabled = shortcutItem.keyEquivalent.isEmpty
            settings.shortcutEnabled.state = .on; act(settings.shortcutEnabled)
            checks["shortcuts.disable_restore"] = disabled && shortcutItem.keyEquivalent == "r" && NSDictionary(dictionary: retained ?? [:]).isEqual(to: settings.defaults.dictionary(forKey: AppShortcuts.bindingKey) ?? [:])
            let before = settings.shortcuts.binding.dictionary
            var reserved = false, conflict = false
            do { try settings.shortcuts.setBinding(.init(key: "q", modifiers: .command)) } catch { reserved = true }
            let foreign = NSMenuItem(title: "Existing action", action: nil, keyEquivalent: "p")
            foreign.keyEquivalentModifierMask = .command; root.addItem(foreign)
            do { try settings.shortcuts.setBinding(.init(key: "p", modifiers: .command)) } catch { conflict = true }
            checks["shortcuts.conflict_or_reserved_keys"] = reserved && conflict && NSDictionary(dictionary: before).isEqual(to: settings.shortcuts.binding.dictionary)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let result = try AppLifecycleUI.shared.offscreenSnapshot(to: directory.appendingPathComponent("settings-\(name).png"), appearance: appearance)
                for (key, passed) in result { checks["settings.\(name).\(key)"] = passed }
            }
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            let views = app.windows.compactMap(\.contentView).flatMap(descendants)
            let options = views.compactMap { $0 as? NSSwitch }.filter { NSStringFromSelector($0.action ?? #selector(ProductSettings.changed(_:))).contains("changedUpdateOption") }
            if let toggle = options.first {
                toggle.state = .on; act(toggle)
                checks["updates.real_options_control"] = AppUpdatePreferences.options(Bundle.main.bundleIdentifier!).automaticCheck
            } else { checks["updates.real_options_control"] = false }
            AppLifecycleUI.shared.checkForUpdates(present: false)
            let deadline = Date().addingTimeInterval(15)
            var resultVisible = false
            while Date() < deadline && !resultVisible {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                resultVisible = views.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("999.0.1") && $0.stringValue.contains("当前") }
            }
            checks["updates.real_check_result_in_window"] = resultVisible
            checks["settings.no_visible_windows_or_dock"] = app.activationPolicy() == .prohibited && app.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow }
            let observed: [String: Any] = ["checks": checks,
                "visible_status_labels": views.compactMap { ($0 as? NSTextField)?.stringValue },
                "update_status": AppUpdatePreferences.status(Bundle.main.bundleIdentifier!, source: ProductLifecycle.updateSource())]
            try JSONSerialization.data(withJSONObject: observed, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("ui.json"), options: .atomic)
            exit(checks.values.allSatisfy { $0 } ? 0 : 1)
        } catch {
            fputs("Product basics self-test: \(error)\n", stderr); exit(1)
        }
    }
}
