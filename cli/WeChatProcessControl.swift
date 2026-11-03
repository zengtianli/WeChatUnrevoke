import AppKit
import Foundation

/// The confirmation flag is checked by the caller. Only the selected app may
/// receive a cooperative termination request; helper processes are never killed.
struct WeChatProcessControl {
    var requestQuit: (String) -> Bool
    var reopen: (String) -> Bool
    var pause: () -> Void = { Thread.sleep(forTimeInterval: 1) }

    func quitAndWait(target: String, isRunning: () -> Bool?) -> Bool {
        guard requestQuit(target) else { return false }
        for _ in 0..<20 {
            pause()
            guard let running = isRunning() else { return false }
            if !running { return true }
        }
        return false
    }

    static let live = WeChatProcessControl(requestQuit: { path in
        let selected = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.tencent.xinWeChat")
            .filter { $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == selected }
        guard !apps.isEmpty else { return false }
        return apps.map { $0.terminate() }.allSatisfy { $0 }
    }, reopen: { path in
        let state = ReopenState()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration) { _, error in
            state.lock.lock()
            state.completed = true
            state.succeeded = error == nil
            state.lock.unlock()
        }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            state.lock.lock()
            let result = state.completed ? state.succeeded : nil
            state.lock.unlock()
            if let result { return result }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return false
    })
}

private final class ReopenState: @unchecked Sendable {
    let lock = NSLock()
    var completed = false
    var succeeded = false
}
