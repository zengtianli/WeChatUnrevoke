// Shared opt-in application menu shortcuts. No global event tap or automatic global bindings.
#if os(macOS)
import AppKit

final class AppShortcuts: NSObject {
    static let enabledKey = "appShortcuts.refresh.enabled"
    static let bindingKey = "appShortcuts.refresh.binding"
    static let portableKeys = [enabledKey, bindingKey]
    struct Binding {
        var key: String
        var modifiers: NSEvent.ModifierFlags
        var dictionary: [String: Any] { ["key": key, "modifiers": modifiers.rawValue] }
    }
    let defaults: UserDefaults
    private let action: () -> Void
    private(set) var menuItem: NSMenuItem?
    var enabled: Bool { defaults.object(forKey: Self.enabledKey) == nil || defaults.bool(forKey: Self.enabledKey) }
    var binding: Binding {
        if let value = defaults.dictionary(forKey: Self.bindingKey),
           let key = value["key"] as? String, let flags = value["modifiers"] as? NSNumber {
            let candidate = Binding(key: key, modifiers: NSEvent.ModifierFlags(rawValue: flags.uintValue))
            if (try? Self.validate(candidate)) != nil { return candidate }
        }
        return Binding(key: "r", modifiers: .command)
    }
    init(defaults: UserDefaults = .standard, action: @escaping () -> Void) {
        self.defaults = defaults; self.action = action
        super.init()
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
        guard let menu else { return false }
        for item in menu.items {
            if item !== menuItem, item.keyEquivalent.lowercased() == binding.key.lowercased(),
               item.keyEquivalentModifierMask.intersection([.command, .control, .option, .shift]) == binding.modifiers { return true }
            if conflicts(binding, menu: item.submenu) { return true }
        }
        return false
    }
    func setBinding(_ binding: Binding) throws {
        try Self.validate(binding)
        guard !conflicts(binding) else { throw AppUpdateError("此应用菜单已使用这个组合，原快捷键保持不变。") }
        defaults.set(binding.dictionary, forKey: Self.bindingKey); defaults.synchronize(); refresh()
    }
    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey); defaults.synchronize(); refresh()
    }
    func installMenu() {
        guard menuItem == nil, let root = NSApp.mainMenu else { return }
        let menu = NSMenu(title: ShortcutText.pick("Actions", "操作"))
        let item = NSMenuItem(title: ShortcutText.pick("Refresh", "刷新"), action: #selector(performAction), keyEquivalent: "")
        item.target = self; menu.addItem(item); menuItem = item
        let parent = NSMenuItem(title: menu.title, action: nil, keyEquivalent: ""); parent.submenu = menu
        root.addItem(parent); refresh()
    }
    func refresh() {
        menuItem?.keyEquivalent = enabled ? binding.key : ""
        menuItem?.keyEquivalentModifierMask = binding.modifiers
    }
    // Disabling the key clears keyEquivalent; clicking the ordinary menu action remains useful.
    @objc func performAction() { action() }
    private var comboText: String {
        (binding.modifiers.contains(.control) ? "⌃" : "") + (binding.modifiers.contains(.option) ? "⌥" : "") +
        (binding.modifiers.contains(.shift) ? "⇧" : "") + "⌘" + binding.key.uppercased()
    }
    /// CLI/JSON contract: stays byte-identical whatever the system language is.
    var descriptionText: String {
        (enabled ? "已启用：" : "已关闭，配置保留：") + comboText + "（只在本 App 内生效）"
    }
    /// Window text in the user's language; never put it in CLI output.
    var displayText: String {
        (enabled ? ShortcutText.pick("On: ", "已启用：") : ShortcutText.pick("Off, setting kept: ", "已关闭，配置保留：")) +
        comboText + ShortcutText.pick(" (only inside this app)", "（只在本 App 内生效）")
    }
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
