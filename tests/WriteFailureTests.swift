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
              patch|restore) \(patch);;
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

        // Issues #1 / #3: this build's updater cannot be blocked. Anti-recall and the update
        // block are independent, so the default action still applies anti-recall — no extra
        // prompt, no error — and the fresh check reports antiRevokeOnly with the reason.
        let partial = resources.appendingPathComponent("partial.json")
        try doctor("partial")
        try fm.copyItem(at: fixture, to: partial)
        let onlyRevoke = resources.appendingPathComponent("anti-revoke-only.json")
        let object: [String: Any] = [
            "overall": "antiRevokeOnly", "build": "269602", "app_path": app.path,
            "config_known": true, "running": false, "writable": true,
            "entitlements_ok": true, "entitlement_key_count": 15,
            "anti_revoke_keeptip": "patched", "update_block": "notApplicable",
            "update_source": "App Store install"
        ]
        try JSONSerialization.data(withJSONObject: object).write(to: onlyRevoke)
        try doctor()
        try engine("""
        case " $* " in
          *" --no-block-update "*) echo 'MUST NOT PASS --no-block-update'; exit 1;;
          *) /bin/cp \(Engine.shellQuote(onlyRevoke.path)) \(Engine.shellQuote(fixture.path)); echo 'Update block: NOT applied — App Store install';;
        esac
        """)
        var confirmations = 0
        let independent = AppModel(confirmAction: { _, _, _ in confirmations += 1; return true })
        await independent.refresh()
        await independent.protectNow()
        precondition(confirmations == 0)
        precondition(independent.status?.overall == .antiRevokeOnly)
        precondition(independent.status?.updateBlock == "notApplicable")
        precondition(independent.errorMessage == nil)
        precondition(independent.lastLog.contains("Update block: NOT applied"))
        precondition(defaults.bool(forKey: "everProtected"))
        print("PASS: anti-recall applies on its own when the update block is impossible")

        // Background checks must treat antiRevokeOnly as done, not re-patch it forever.
        defaults.set(true, forKey: "autoRepatch")
        let repatchMarker = resources.appendingPathComponent("auto-repatch-ran")
        try engine("/usr/bin/touch \(Engine.shellQuote(repatchMarker.path)); exit 0")
        let background = AppModel()
        await background.refresh()
        precondition(background.status?.overall == .antiRevokeOnly)
        precondition(!fm.fileExists(atPath: repatchMarker.path))
        defaults.set(false, forKey: "autoRepatch")
        print("PASS: antiRevokeOnly does not trigger automatic re-patching")

        // Periodic doctor must not publish the transient unsigned bundle while
        // the engine is still signing; the final unconditional check must run.
        let midWrite = resources.appendingPathComponent("signing.json")
        let marker = resources.appendingPathComponent("signing-started")
        try doctor("brokenBundle")
        try fm.copyItem(at: fixture, to: midWrite)
        try doctor()
        try engine("/bin/cp \(Engine.shellQuote(midWrite.path)) \(Engine.shellQuote(fixture.path)); /usr/bin/touch \(Engine.shellQuote(marker.path)); /bin/sleep 2; /bin/cp \(Engine.shellQuote(protected.path)) \(Engine.shellQuote(fixture.path)); echo signed")
        let signing = AppModel()
        await signing.refresh()
        let writing = Task { await signing.protectNow() }
        for _ in 0..<100 {
            if fm.fileExists(atPath: marker.path) { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        precondition(fm.fileExists(atPath: marker.path) && signing.isBusy)
        await signing.refresh()
        precondition(signing.status?.overall == .unprotected)
        await writing.value
        precondition(signing.status?.overall == .protected && !signing.isBusy)
        print("PASS: periodic refresh skips intermediate signing state; final check still runs")

        // #1: exact administrator-wrapper output reported for build 269631.
        // The fixture reproduces the output, not macOS's TCC authorization dialog.
        let denied = """
        0:269: execution error: Error: You don’t have permission to save the file “wechat.dylib” in the folder “Resources”.
        ------ Version ------
        WeChat version: 269631
        ------ Config ------
        Matched config: build 269631, targets: revoke, revoke-keeptip, update
        ------ Patch ------
        Variant: keeptip
        Block auto-update: yes
        ------ Target: revoke-keeptip (Contents/Resources/wechat.dylib) ------ (1)
        """
        try doctor()
        try engine("printf '%s' \(Engine.shellQuote(denied)) >&2; exit 1")
        let permissions = AppModel(confirmAction: { _, _, _ in true })
        await permissions.refresh()
        await permissions.protectNow()
        precondition(permissions.status?.overall == .unprotected && !permissions.isBusy)
        precondition(permissions.errorMessage == L.err_writePermissionDenied)
        precondition(permissions.lastLog == denied)
        await permissions.refresh()
        precondition(permissions.errorMessage == L.err_writePermissionDenied)
        print("PASS: reported 269631 permission error gives recovery steps and retains exact diagnostics")

        // Restore has the same permission handling, including failure after a write.
        try engine("/bin/cp \(Engine.shellQuote(partial.path)) \(Engine.shellQuote(fixture.path)); printf '%s' \(Engine.shellQuote(denied)) >&2; exit 1")
        await permissions.restoreNow()
        precondition(permissions.status?.overall == .partial)
        precondition(permissions.errorMessage == L.err_writePermissionDenied)
        precondition(permissions.lastLog == denied)
        print("PASS: permission failure during restore still refreshes the actual partial state")

        // Exact output of the real engine when its pre-write backup copy is denied
        // (captured from a disposable WeChat copy whose Resources folder refused new files).
        let copyDenied = """
        ------ Version ------
        WeChat version: 269579
        ------ Config ------
        Matched config: build 269579, targets: revoke, revoke-keeptip, update
        ------ Patch ------
        Variant: keeptip
        Block auto-update: yes
        ------ Target: revoke-keeptip (Contents/Resources/wechat.dylib) ------
        ------ Target: update (Contents/Resources/wechat.dylib) ------

        Error: “wechat.dylib” couldn’t be copied because you don’t have permission to access “Resources”.

        """
        try engine("printf '%s' \(Engine.shellQuote(copyDenied)) >&2; exit 1")
        await permissions.protectNow()
        precondition(permissions.errorMessage == L.err_writePermissionDenied)
        precondition(permissions.lastLog == copyDenied)
        print("PASS: real engine backup-copy denial gives recovery steps and retains exact diagnostics")

        for output in ["Error: Permission denied", "codesign: Operation not permitted",
                       "Error: “wechat.dylib” couldn’t be moved because you don’t have permission to access “Resources”.",
                       "Error: “wechat.dylib.269579.bak” couldn’t be removed because you don’t have permission to access it.",
                       "Error: The file “wechat.dylib” couldn’t be opened because you don’t have permission to view it.",
                       "Error Domain=NSCocoaErrorDomain Code=257", "未能拷贝“wechat.dylib”，因为您没有权限访问“Resources”。",
                       "Error Domain=NSCocoaErrorDomain Code=513", "您没有权限将文件存储到文件夹中。",
                       "您没有将文件“wechat.dylib”存储到文件夹“Resources”中的权限。",
                       "您沒有將檔案儲存至檔案夾的權限。"] {
            try engine("printf '%s' \(Engine.shellQuote(output)) >&2; exit 1")
            await permissions.protectNow()
            precondition(permissions.errorMessage == L.err_writePermissionDenied)
            precondition(permissions.lastLog == output)
        }
        for output in ["Error: expected bytes mismatch", "Error: Unsupported version: 999999",
                       "Error: No space left on device", "Error Domain=NSCocoaErrorDomain Code=5130"] {
            try engine("printf '%s' \(Engine.shellQuote(output)) >&2; exit 1")
            await permissions.protectNow()
            precondition(permissions.errorMessage == output)
        }
        print("PASS: write-permission variants are recognized; unrelated errors stay unchanged")

        // Permission denial must not cause another write every 60-second refresh.
        let attempts = resources.appendingPathComponent("write-attempts")
        try doctor()
        try engine("echo attempt >> \(Engine.shellQuote(attempts.path)); printf '%s' \(Engine.shellQuote(copyDenied)) >&2; exit 1")
        defaults.set(true, forKey: "autoRepatch")
        defaults.set(true, forKey: "everProtected")
        let automatic = AppModel()
        await automatic.refresh()
        precondition(automatic.errorMessage == L.err_writePermissionDenied)
        await automatic.refresh()
        await automatic.refresh()
        let recordedAttempts = try String(contentsOf: attempts, encoding: .utf8)
        precondition(recordedAttempts == "attempt\n")
        try engine("/bin/cp \(Engine.shellQuote(protected.path)) \(Engine.shellQuote(fixture.path)); echo patched")
        await automatic.protectNow()
        precondition(automatic.status?.overall == .protected && automatic.errorMessage == nil)
        precondition(automatic.lastLog.contains("patched"))
        print("PASS: permission denial pauses background writes; explicit successful retry clears the error")

        // Periodic checks run the engine only when the WeChat bundle changed on disk.
        defaults.set(false, forKey: "autoRepatch")
        let doctorRuns = resources.appendingPathComponent("doctor-runs")
        let counting = """
        #!/bin/sh
        case "$1" in
          doctor) echo run >> \(Engine.shellQuote(doctorRuns.path)); /bin/cat \(Engine.shellQuote(fixture.path));;
          *) exit 99;;
        esac
        """
        try counting.write(to: cli, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        func runs() -> Int {
            ((try? String(contentsOf: doctorRuns, encoding: .utf8)) ?? "").split(separator: "\n").count
        }
        try doctor("protected")
        let idle = AppModel()
        await idle.refresh()
        precondition(runs() == 1)
        await idle.periodicCheck()
        await idle.periodicCheck()
        precondition(runs() == 1 && idle.status?.overall == .protected)
        let dylib = app.appendingPathComponent("Contents/Resources/wechat.dylib")
        try fm.createDirectory(at: dylib.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("replaced".utf8).write(to: dylib)
        try doctor()
        await idle.periodicCheck()
        precondition(runs() == 2 && idle.status?.overall == .unprotected)
        await idle.periodicCheck()
        precondition(runs() == 2)
        print("PASS: periodic check skips the engine until the WeChat bundle changes")
    }
}
