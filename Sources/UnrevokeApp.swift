import SwiftUI
import AppKit

// =============================================================================
// Unrevoke — 给 macOS 微信打防撤回补丁的图形界面
//
// 引擎是 https://github.com/zengtianli/WeChatTweak（AGPL-3.0），构建期整个拷进
// Contents/Resources/。这一层只做界面：状态渲染、流程编排、出错时的人话。
// =============================================================================

extension Notification.Name {
    static let consoleRefresh = Notification.Name("consoleRefresh")
    static let unrevokePreferencesChanged = Notification.Name("UnrevokePreferencesChanged")
}

@main
@MainActor
enum UnrevokeEntry {
    static func main() {
        if let code = AppCommandMode.run(arguments: Array(CommandLine.arguments.dropFirst())) {
            exit(code)
        } else if CommandLine.arguments.contains("--ui-self-test") {
            NativeUISelfTest.launch()
        } else if CommandLine.arguments.contains("--background-measure") && LaneSignal.quiet {
            UnrevokeQuietMeasure.launch()
        } else {
            UnrevokeApp.main()
        }
    }
}

/// Real doctor status in the production view, rendered offscreen without starting
/// periodic checks, config updates, automatic patching or preference synchronization.
@MainActor
enum UnrevokeQuietMeasure {
    static func launch() {
        let application = NSApplication.shared
        LaneSignal.enterQuietIfAsked()
        let model = AppModel(readOnly: true)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 620, height: 720),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: ContentView(model: model, automaticallyStart: false))
        window.contentView = view
        let timeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in NSApp.terminate(nil) }
        Task { @MainActor in
            await model.refresh()
            guard model.status != nil, model.errorMessage == nil else {
                NSApp.terminate(nil)
                return
            }
            DispatchQueue.main.async {
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    NSApp.terminate(nil)
                    return
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                timeout.invalidate()
                LaneSignal.ready("doctor")
            }
        }
        application.run()
        withExtendedLifetime(window) {}
    }
}

struct UnrevokeApp: App {
    init() {
        let configuration = ProductLifecycle.makeConfiguration()
        configuration.onChange = {
            NotificationCenter.default.post(name: .unrevokePreferencesChanged, object: nil)
        }
        AppLifecycleCLI.follow(configuration)
        AppLifecycleUI.install(name: ProductLifecycle.name, configuration: configuration,
                               updateSource: ProductLifecycle.updateSource())
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 620, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu(L.t("操作", "Actions")) {
                Button(L.btn_recheck) {
                    NotificationCenter.default.post(name: .consoleRefresh, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
