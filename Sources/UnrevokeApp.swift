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
}

@main
struct UnrevokeApp: App {
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
