import Foundation

/// Compiled alongside unchanged production sources. Only the external engine is a
/// fault fixture, allowing failures without touching WeChat or asking for root.
@main
struct RecoveryAcceptance {
    struct CheckFailure: Error, CustomStringConvertible {
        let description: String
    }

    @MainActor static func main() async throws {
        let fm = FileManager.default
        let resources = Bundle.main.resourceURL!
        let identifier = Bundle.main.bundleIdentifier!
        guard identifier.hasPrefix("io.github.zengtianli.unrevoke.accept.recovery.") else {
            throw CheckFailure(description: "Refusing a non-disposable preferences domain")
        }
        let defaults = UserDefaults.standard
        defer { defaults.removePersistentDomain(forName: identifier) }
        let cli = resources.appendingPathComponent("wechattweak")
        let fixture = resources.appendingPathComponent("doctor.json")
        let doctorCalls = resources.appendingPathComponent("doctor-calls")
        let writeCalls = resources.appendingPathComponent("write-calls")
        let app = resources.appendingPathComponent("WeChat.app")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        defaults.set(app.path, forKey: "weChatPath")
        defaults.set(false, forKey: "autoRepatch")
        defaults.set(false, forKey: "everProtected")

        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw CheckFailure(description: message) }
        }
        func count(_ file: URL) -> Int {
            ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").count
        }
        func doctor(_ overall: String = "unprotected", running: Bool = false) throws {
            let object: [String: Any] = [
                "overall": overall, "build": "269631", "app_path": app.path,
                "config_known": true, "running": running, "writable": true,
                "entitlements_ok": true, "entitlement_key_count": 15
            ]
            try JSONSerialization.data(withJSONObject: object).write(to: fixture)
        }
        func engine(_ write: String) throws {
            let script = """
            #!/bin/sh
            case "$1" in
              doctor) echo doctor >> \(Engine.shellQuote(doctorCalls.path)); /bin/cat \(Engine.shellQuote(fixture.path));;
              patch|restore) echo "$1" >> \(Engine.shellQuote(writeCalls.path)); \(write);;
              *) exit 99;;
            esac
            """
            try script.write(to: cli, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        }

        // Never authorize quitting a real WeChat process, even if a fixture regresses.
        let model = AppModel(confirmAction: { title, _, _ in title == L.flow_restoreConfirm })
        try doctor()
        try engine("echo 'injected write failure' >&2; exit 42")
        await model.refresh()
        let beforeFailure = count(doctorCalls)
        await model.protectNow()
        try check(count(doctorCalls) == beforeFailure + 2, "Failure skipped preflight or final doctor")
        try check(model.status?.overall == .unprotected && !model.isBusy, "Failure left stale/busy state")
        try check(model.lastLog.contains("injected write failure"), "Failure lost engine diagnostics")
        await model.refresh()
        try check(model.errorMessage?.contains("injected write failure") == true, "Refresh erased write error")
        print("PASS: nonzero write always rechecks actual state and preserves diagnostics across refresh")

        // Snapshot used only by the fixture. No real patch or signature is claimed.
        let protected = resources.appendingPathComponent("protected.json")
        try doctor("protected")
        try fm.copyItem(at: fixture, to: protected)
        try doctor()
        try engine("/bin/cp \(Engine.shellQuote(protected.path)) \(Engine.shellQuote(fixture.path)); echo 'failed after mutation' >&2; exit 42")
        await model.protectNow()
        try check(model.status?.overall == .protected, "Partial mutation was hidden by failed exit")
        try check(model.errorMessage?.contains("failed after mutation") == true, "Partial failure lost its cause")
        print("PASS: write failure after mutation reports actual protected state and its separate error")

        try engine("/bin/cp \(Engine.shellQuote(protected.path)) \(Engine.shellQuote(fixture.path)); echo retried")
        await model.protectNow()
        try check(model.status?.overall == .protected && model.errorMessage == nil && !model.isBusy, "Successful retry did not recover")
        try check(model.lastLog.contains("retried"), "Retry did not replace diagnostics")
        print("PASS: explicit successful retry clears the previous failure")

        let partial = resources.appendingPathComponent("partial.json")
        try doctor("partial")
        try fm.copyItem(at: fixture, to: partial)
        let denial = "Error: Permission denied while restoring fixture"
        try engine("/bin/cp \(Engine.shellQuote(partial.path)) \(Engine.shellQuote(fixture.path)); printf '%s' \(Engine.shellQuote(denial)) >&2; exit 1")
        let beforeRestore = count(doctorCalls)
        await model.restoreNow()
        try check(count(doctorCalls) == beforeRestore + 2, "Restore failure skipped final doctor")
        try check(model.status?.overall == .partial && !model.isBusy, "Restore failure hid partial state")
        try check(model.errorMessage == L.err_writePermissionDenied && model.lastLog == denial, "Permission recovery guidance/diagnostics missing")
        print("PASS: restore permission failure refreshes partial state and retains recovery guidance plus exact log")

        let unprotected = resources.appendingPathComponent("unprotected.json")
        try doctor()
        try fm.copyItem(at: fixture, to: unprotected)
        try engine("/bin/cp \(Engine.shellQuote(unprotected.path)) \(Engine.shellQuote(fixture.path)); echo restored")
        await model.restoreNow()
        try check(model.status?.overall == .unprotected && model.errorMessage == nil, "Restore retry did not recover")
        try check(!defaults.bool(forKey: "everProtected"), "Restore retry retained auto-repatch eligibility")
        print("PASS: successful restore retry clears failure and auto-repatch eligibility")

        // The displayed state is closed; the fresh preflight observes it running.
        try doctor(running: true)
        let writesBefore = count(writeCalls)
        await model.protectNow()
        try check(count(writeCalls) == writesBefore, "Preflight wrote while fixture reports running")
        try check(model.errorMessage != nil && !model.isBusy, "Preflight rejection did not recover busy state")
        print("PASS: fresh running-process preflight rejects a write without any process termination")

        try doctor()
        await model.refresh()
        let marker = resources.appendingPathComponent("write-started")
        let signing = resources.appendingPathComponent("signing.json")
        try doctor("brokenBundle")
        try fm.copyItem(at: fixture, to: signing)
        try doctor()
        try engine("/bin/cp \(Engine.shellQuote(signing.path)) \(Engine.shellQuote(fixture.path)); /usr/bin/touch \(Engine.shellQuote(marker.path)); /bin/sleep 1; /bin/cp \(Engine.shellQuote(protected.path)) \(Engine.shellQuote(fixture.path)); echo recovered")
        let writesAtStart = count(writeCalls)
        let writing = Task { await model.protectNow() }
        for _ in 0..<100 {
            if fm.fileExists(atPath: marker.path) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try check(fm.fileExists(atPath: marker.path) && model.isBusy, "Fixture write failed to begin")
        await model.refresh()
        await model.protectNow()
        await model.restoreNow()
        try check(model.status?.overall == .unprotected, "Concurrent refresh exposed intermediate signing state")
        await writing.value
        try check(count(writeCalls) == writesAtStart + 1, "Concurrent actions launched duplicate writes")
        try check(model.status?.overall == .protected && !model.isBusy, "Final refresh did not replace signing state")
        print("PASS: concurrent refresh and write actions do not expose intermediate state or duplicate writes")

        try "not-json".write(to: fixture, atomically: true, encoding: .utf8)
        await model.refresh()
        try check(model.errorMessage != nil && !model.isBusy, "Malformed doctor data failed silently")
        try doctor("protected")
        await model.refresh()
        try check(model.status?.overall == .protected && model.errorMessage == nil, "Doctor recovery did not clear decode error")
        print("PASS: malformed doctor response is visible and the next valid refresh recovers")

        try fm.removeItem(at: cli)
        await model.refresh()
        try check(model.errorMessage == L.err_cliMissing, "Missing bundled engine fell back or failed silently")
        try engine("echo recovered")
        await model.refresh()
        try check(model.status?.overall == .protected && model.errorMessage == nil, "Restored engine did not recover")
        print("PASS: missing bundled engine reports a recoverable error without a PATH fallback")
    }
}
