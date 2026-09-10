import Foundation

// Runs the real AppModel -> Engine -> child-process path against an isolated CLI fixture.
@main
struct WriteFailureTests {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let resources = Bundle.main.resourceURL!
        let cli = resources.appendingPathComponent("wechattweak")
        let fixture = resources.appendingPathComponent("doctor.json")
        let app = resources.appendingPathComponent("WeChat.app")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        defaults.set(app.path, forKey: "weChatPath")
        defaults.set(false, forKey: "autoRepatch")
        defer {
            for key in ["weChatPath", "autoRepatch", "lastBuild", "everProtected", "variant"] {
                defaults.removeObject(forKey: key)
            }
        }
        func doctor(_ overall: String = "unprotected", running: Bool = false) throws {
            let object: [String: Any] = [
                "overall": overall, "build": "269136", "app_path": app.path,
                "config_known": true, "running": running, "writable": true,
                "entitlements_ok": true, "entitlement_key_count": 15
            ]
            try JSONSerialization.data(withJSONObject: object).write(to: fixture)
        }
        func engine(_ patch: String) throws {
            let script = """
            #!/bin/sh
            case "$1" in
              doctor) /bin/cat \(Engine.shellQuote(fixture.path));;
              patch) \(patch);;
              *) exit 99;;
            esac
            """
            try script.write(to: cli, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        }
        try doctor()
        try engine("echo 'update locator failed for 269136' >&2; exit 42")
        let model = AppModel()
        await model.refresh()
        await model.protectNow()
        precondition(model.status?.overall == .unprotected)
        precondition(model.lastLog.contains("update locator failed for 269136"))
        precondition(model.errorMessage?.contains("update locator failed for 269136") == true)
        precondition(!model.isBusy)
        await model.refresh()
        precondition(model.errorMessage?.contains("update locator failed for 269136") == true)
        print("PASS: nonzero engine output survives post-write and periodic doctor")

        // A process starting after the displayed check must prevent patch invocation.
        try doctor(running: true)
        try engine("echo 'PATCH MUST NOT RUN'; exit 0")
        await model.protectNow()
        precondition(!model.lastLog.contains("PATCH MUST NOT RUN"))
        precondition(model.errorMessage != nil)
        print("PASS: fresh preflight rejects running WeChat")

        try doctor()
        await model.refresh()
        let protected = resources.appendingPathComponent("protected.json")
        try doctor("protected")
        try fm.copyItem(at: fixture, to: protected)
        try doctor()
        try engine("/bin/cp \(Engine.shellQuote(protected.path)) \(Engine.shellQuote(fixture.path)); echo 'failed after writing' >&2; exit 42")
        await model.protectNow()
        precondition(model.status?.overall == .protected)
        precondition(model.errorMessage?.contains("failed after writing") == true)
        print("PASS: failed write still refreshes actual state and retains its error")

        try engine("/bin/cp \(Engine.shellQuote(protected.path)) \(Engine.shellQuote(fixture.path)); echo patched")
        await model.protectNow()
        precondition(model.status?.overall == .protected)
        precondition(model.errorMessage == nil)
        precondition(model.lastLog.contains("patched"))
        print("PASS: successful retry clears the prior write error")

        // Reproduce #1038: the old updater class is absent. The default must fail;
        // only explicit consent may send the CLI's existing --no-block-update option.
        let partial = resources.appendingPathComponent("partial.json")
        try doctor("partial")
        try fm.copyItem(at: fixture, to: partial)
        try doctor()
        try engine("""
        case " $* " in
          *" --no-block-update "*) /bin/cp \(Engine.shellQuote(partial.path)) \(Engine.shellQuote(fixture.path)); echo 'Block auto-update: no';;
          *) echo 'auto-locate(update): Objective-C class XAppUpdateManager not found' >&2; exit 1;;
        esac
        """)
        var confirmations = 0
        let fallback = AppModel(confirmAction: { _, _, _ in confirmations += 1; return true })
        await fallback.refresh()
        await fallback.protectNow()
        precondition(confirmations == 0)
        precondition(fallback.status?.overall == .unprotected)
        precondition(fallback.errorMessage?.contains("XAppUpdateManager not found") == true)
        await fallback.protectNow(blockUpdate: false)
        precondition(confirmations == 1)
        precondition(fallback.status?.overall == .partial)
        precondition(fallback.errorMessage == nil)
        precondition(fallback.lastLog.contains("Block auto-update: no"))
        precondition(fallback.toast == L.flow_withoutUpdateDone)
        print("PASS: default fails closed; explicit consent applies anti-recall only and retains partial verdict")

        try doctor()
        let canceled = AppModel(confirmAction: { _, _, _ in false })
        await canceled.refresh()
        await canceled.protectNow(blockUpdate: false)
        precondition(canceled.status?.overall == .unprotected)
        precondition(canceled.lastLog.isEmpty)
        print("PASS: canceling the fallback confirmation does not run the patch")
    }
}
