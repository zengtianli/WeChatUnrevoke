// Shared action shortcuts. Application scope by default; global scope is explicitly selected.
#if os(macOS)
import AppKit
import Carbon.HIToolbox

final class AppShortcuts: NSObject {
    static let enabledKey = "appShortcuts.refresh.enabled"
    static let bindingKey = "appShortcuts.refresh.binding"
    static let portableKeys = [enabledKey, bindingKey]
    static func portableKeys(for identifier: String) -> [String] {
        ["appShortcuts.\(identifier).enabled", "appShortcuts.\(identifier).binding", "appShortcuts.\(identifier).scope", "appShortcuts.\(identifier).cleared"]
    }
    enum Scope: String { case application, global }
    var scope: Scope { Scope(rawValue: defaults.string(forKey: Self.portableKeys(for: identifier)[2]) ?? "") ?? .application }
    private(set) var registrationError: String?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var registered: Binding?
    private static var serial: UInt32 = 0
    private let hotKeyID: UInt32
    private static var live: [UInt32: Binding] = [:]
    var globallyRegistered: Bool { hotKey != nil }
    var carbonIdentity: EventHotKeyID { EventHotKeyID(signature: 0x4150534B, id: hotKeyID) }
    var cleared: Bool { defaults.bool(forKey: Self.portableKeys(for: identifier)[3]) }
    private var recording = false
    func setRecording(_ value: Bool) { recording = value; refresh() }
    func clear() {
        defaults.set(true, forKey: Self.portableKeys(for: identifier)[3])
        defaults.removeObject(forKey: bindingPreference); setEnabled(false)
    }
    struct Binding {
        var key: String
        var modifiers: NSEvent.ModifierFlags
        var dictionary: [String: Any] { ["key": key, "modifiers": modifiers.rawValue] }
    }
    let defaults: UserDefaults
    let identifier: String
    private let title: String
    private let fallback: Binding
    private var enabledPreference: String { Self.portableKeys(for: identifier)[0] }
    private var bindingPreference: String { Self.portableKeys(for: identifier)[1] }
    private let action: () -> Void
    private(set) var menuItem: NSMenuItem?
    var enabled: Bool { !cleared && (defaults.object(forKey: enabledPreference) == nil || defaults.bool(forKey: enabledPreference)) }
    var binding: Binding {
        if let value = defaults.dictionary(forKey: bindingPreference),
           let key = value["key"] as? String, let flags = value["modifiers"] as? NSNumber {
            let candidate = Binding(key: key, modifiers: NSEvent.ModifierFlags(rawValue: flags.uintValue))
            if (try? Self.validate(candidate)) != nil { return candidate }
        }
        return fallback
    }
    init(defaults: UserDefaults = .standard, identifier: String = "refresh", title: String? = nil,
         defaultBinding: Binding = Binding(key: "r", modifiers: .command), action: @escaping () -> Void) {
        self.defaults = defaults; self.action = action; self.identifier = identifier
        self.title = title ?? ShortcutText.pick("Refresh", "刷新"); self.fallback = defaultBinding
        Self.serial += 1; hotKeyID = Self.serial
        super.init()
    }
    deinit { releaseGlobal(); if let handler { RemoveEventHandler(handler) } }
    private static let codes: [String: UInt32] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46]
    static func keyName(code: UInt16) -> String? { codes.first { $0.value == UInt32(code) }?.key }
    private func releaseGlobal() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil; registered = nil; Self.live.removeValue(forKey: hotKeyID)
    }
    private func registerGlobal(_ candidate: Binding) throws {
        if let registered, registered.key == candidate.key && registered.modifiers == candidate.modifiers { return }
        guard let code = Self.codes[candidate.key.lowercased()] else { throw AppUpdateError("全局快捷键请使用字母或数字。") }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
            let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var key = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
                let owner = Unmanaged<AppShortcuts>.fromOpaque(context).takeUnretainedValue()
                guard result == noErr, key.signature == 0x4150534B, key.id == owner.hotKeyID else { return OSStatus(eventNotHandledErr) }
                owner.performAction(); return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard result == noErr else { throw AppUpdateError("无法安装全局快捷键处理器（\(result)）。") }
        }
        var modifiers: UInt32 = 0
        for (flag, value) in [(NSEvent.ModifierFlags.command, cmdKey), (.option, optionKey), (.control, controlKey), (.shift, shiftKey)] {
            if candidate.modifiers.contains(flag) { modifiers |= UInt32(value) }
        }
        var newRef: EventHotKeyRef?
        let result = RegisterEventHotKey(code, modifiers, EventHotKeyID(signature: 0x4150534B, id: hotKeyID), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &newRef)
        guard result == noErr else { throw AppUpdateError("系统拒绝注册全局快捷键（\(result)），原设置保持不变。") }
        releaseGlobal(); hotKey = newRef; registered = candidate; Self.live[hotKeyID] = candidate
    }
    func setScope(_ scope: Scope) throws {
        guard !conflicts(binding) else { throw AppUpdateError("此组合已被其他操作使用，原设置保持不变。") }
        if scope == .global && enabled && menuItem != nil { try registerGlobal(binding) }
        defaults.set(scope.rawValue, forKey: Self.portableKeys(for: identifier)[2]); defaults.synchronize(); refresh()
    }
    static func validate(_ binding: Binding) throws {
        let allowed: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard binding.key.count == 1, binding.key.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }),
              binding.modifiers.contains(.command), binding.modifiers.subtracting(allowed).isEmpty else {
            throw AppUpdateError("应用快捷键须为 ⌘ 加单个字母或数字，可另加 ⇧、⌥、⌃。")
        }
        let reserved = Set(["q", "w", "h", "m", "c", "v", "x", "z", "a"])
        if binding.modifiers == .command && reserved.contains(binding.key.lowercased()) {
            throw AppUpdateError("此组合保留给系统或编辑菜单，请选择其他快捷键。")
        }
    }
    func conflicts(_ binding: Binding, menu: NSMenu? = NSApp.mainMenu) -> Bool {
        if Self.live.contains(where: { $0.key != hotKeyID && $0.value.key.lowercased() == binding.key.lowercased() && $0.value.modifiers == binding.modifiers }) { return true }
        guard let menu else { return false }
        for item in menu.items {
            if item !== menuItem, item.keyEquivalent.lowercased() == binding.key.lowercased(),
               item.keyEquivalentModifierMask.intersection([.command, .control, .option, .shift]) == binding.modifiers { return true }
            if conflicts(binding, menu: item.submenu) { return true }
        }
        return false
    }
    func setBinding(_ binding: Binding, enable: Bool = false) throws {
        try Self.validate(binding)
        guard !conflicts(binding) else { throw AppUpdateError("此应用菜单已使用这个组合，原快捷键保持不变。") }
        if scope == .global && (enabled || enable) && menuItem != nil { try registerGlobal(binding) }
        if enable {
            defaults.removeObject(forKey: Self.portableKeys(for: identifier)[3])
            defaults.set(true, forKey: enabledPreference)
        }
        defaults.set(binding.dictionary, forKey: bindingPreference); defaults.synchronize(); refresh()
    }
    func setEnabled(_ enabled: Bool) {
        if enabled { defaults.removeObject(forKey: Self.portableKeys(for: identifier)[3]) }
        defaults.set(enabled, forKey: enabledPreference); defaults.synchronize(); refresh()
    }
    func installMenu() {
        guard menuItem == nil, let root = NSApp.mainMenu else { return }
        let parent = root.items.first { $0.identifier?.rawValue == "appShortcuts.actions" } ?? NSMenuItem(title: ShortcutText.pick("Actions", "操作"), action: nil, keyEquivalent: "")
        let menu = parent.submenu ?? NSMenu(title: parent.title)
        let item = NSMenuItem(title: title, action: #selector(performAction), keyEquivalent: "")
        item.target = self; menu.addItem(item); menuItem = item
        parent.identifier = NSUserInterfaceItemIdentifier("appShortcuts.actions"); parent.submenu = menu
        if parent.menu == nil { root.addItem(parent) }
        refresh()
    }
    func refresh() {
        registrationError = nil
        if enabled && !recording && scope == .global && menuItem != nil {
            do { try registerGlobal(binding) } catch { registrationError = error.localizedDescription; releaseGlobal() }
        } else { releaseGlobal() }
        menuItem?.keyEquivalent = enabled && !recording && scope == .application && !conflicts(binding) ? binding.key : ""
        menuItem?.keyEquivalentModifierMask = binding.modifiers
    }
    // Disabling the key clears keyEquivalent; clicking the ordinary menu action remains useful.
    @objc func performAction() { action() }
    var comboText: String {
        (binding.modifiers.contains(.control) ? "⌃" : "") + (binding.modifiers.contains(.option) ? "⌥" : "") +
        (binding.modifiers.contains(.shift) ? "⇧" : "") + "⌘" + binding.key.uppercased()
    }
    /// CLI/JSON contract: stays byte-identical whatever the system language is.
    var descriptionText: String {
        if cleared { return "未设置" }
        return
        registrationError ?? ((enabled ? "已启用：" : "已关闭，配置保留：") + comboText + (scope == .global ? "（全局）" : "（只在本 App 内生效）"))
    }
    /// Window text in the user's language; never put it in CLI output.
    var displayText: String {
        if cleared { return ShortcutText.pick("Not set", "未设置") }
        return
        registrationError ?? ((enabled ? ShortcutText.pick("On: ", "已启用：") : ShortcutText.pick("Off, setting kept: ", "已关闭，配置保留：")) +
        comboText + (scope == .global ? ShortcutText.pick(" (global)", "（全局）") : ShortcutText.pick(" (only inside this app)", "（只在本 App 内生效）")))
    }
}

/// Settings recorder: captures only this app's next key; Escape cancels. No event tap or Accessibility permission.
final class AppShortcutRecorder: NSButton {
    var shortcut: AppShortcuts?
    var changed: (() -> Void)?
    var reportError: ((String) -> Void)?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    init() {
        super.init(frame: .zero); bezelStyle = .rounded; target = self; action = #selector(record)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refreshTitle() { title = shortcut?.cleared == true ? ShortcutText.pick("Record shortcut", "点击录制") : shortcut?.comboText ?? "…" }
    @objc private func record() {
        if monitor != nil { cancel(); return }
        guard let shortcut else { return }
        shortcut.setRecording(true)
        title = ShortcutText.pick("Press keys… Esc cancels", "按下组合键… Esc 取消")
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            self.capture(event); return nil
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in self?.cancel() }
    }
    func capture(_ event: NSEvent) {
        cancel()
        guard event.keyCode != 53, let shortcut else { return }
        do {
            let candidate = AppShortcuts.Binding(key: AppShortcuts.keyName(code: event.keyCode) ?? "", modifiers: event.modifierFlags.intersection([.command, .option, .shift, .control]))
            try shortcut.setBinding(candidate, enable: true); changed?()
        } catch { reportError?(error.localizedDescription) }
        refreshTitle()
    }
    func cancel() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor); self.monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
        shortcut?.setRecording(false); refreshTitle()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { cancel() }; super.viewWillMove(toWindow: newWindow) }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}

/// English or Simplified Chinese for the adapter's own words. Store targets vendor this file without the
/// lifecycle layer (AppLifecycle.swift), so it keeps a private copy of LifecycleText's rule, as CommandPalette does:
/// the product's declared localizations first, otherwise the user's preferred languages; anything not Chinese is
/// English; `APP_LIFECYCLE_LANGUAGE=en|zh-Hans` pins it.
private enum ShortcutText {
    static func pick(_ english: String, _ chinese: String) -> String {
        let pinned = ProcessInfo.processInfo.environment["APP_LIFECYCLE_LANGUAGE"] ?? ""
        let declared = Bundle.main.localizations.filter { $0 != "Base" }
        let order = !pinned.isEmpty ? [pinned]
            : !declared.isEmpty ? Bundle.main.preferredLocalizations.filter { $0 != "Base" } : Locale.preferredLanguages
        return (order.first?.lowercased().hasPrefix("zh") ?? false) ? chinese : english
    }
}
#endif
