import Foundation

@main
struct WriteHistoryTests {
    @MainActor static func main() async throws {
        func check(_ condition: @autoclosure () throws -> Bool) rethrows {
            let result = try condition()
            precondition(result)
        }
        let fm = FileManager.default
        // All preferences and engine fixtures belong to this test app, never the product.
        precondition(Bundle.main.bundleIdentifier?.hasPrefix("io.github.zengtianli.unrevoke.tests") == true)
        precondition(WriteHistoryStore.forProductBundle() == nil)
        let resources = Bundle.main.resourceURL!
        let scratch = resources.appendingPathComponent("write-history-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let recordURL = scratch.appendingPathComponent("history/last-write.json")
        let store = WriteHistoryStore(recordURL: recordURL)
        try check(try store.load() == nil)
        precondition(!fm.fileExists(atPath: recordURL.deletingLastPathComponent().path))
        print("PASS: missing history is nil and read-only loading creates no directory")

        let original = WriteHistoryRecord(action: "patch", succeeded: false,
            lastEngineLog: "fictional raw engine output\n", lastWriteError: "fictional error",
            overall: "partial", completedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try store.save(original)
        try check(try store.load() == original)
        func permissions(_ url: URL) throws -> Int {
            (try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue
        }
        try check(try permissions(recordURL.deletingLastPathComponent()) == 0o700)
        try check(try permissions(recordURL) == 0o600)
        let openedBeforeReplacement = try FileHandle(forReadingFrom: recordURL)
        let successful = WriteHistoryRecord(action: "restore", succeeded: true,
            lastEngineLog: "restored\n", lastWriteError: nil, overall: "unprotected")
        try store.save(successful)
        let oldBytes = try openedBeforeReplacement.readToEnd()!
        try openedBeforeReplacement.close()
        try check(try JSONDecoder().decode(WriteHistoryRecord.self, from: oldBytes) == original)
        try check(try store.load() == successful)
        try check(try permissions(recordURL) == 0o600)
        let encoded = try JSONSerialization.jsonObject(with: Data(contentsOf: recordURL)) as! [String: Any]
        precondition(encoded["lastWriteError"] is NSNull)
        try check(try fm.contentsOfDirectory(atPath: recordURL.deletingLastPathComponent().path) == ["last-write.json"])
        print("PASS: atomic replacement preserves old readers, explicit null, 0700 directory and 0600 file")

        try Data("not JSON".utf8).write(to: recordURL)
        var rejected = false
        do { _ = try store.load() } catch { rejected = true }
        precondition(rejected)
        try fm.removeItem(at: recordURL)
        let outside = scratch.appendingPathComponent("outside.json")
        try Data("untouched".utf8).write(to: outside)
        try fm.createSymbolicLink(at: recordURL, withDestinationURL: outside)
        rejected = false
        do { _ = try store.load() } catch { rejected = true }
        precondition(rejected)
        try store.save(successful)
        try check(try String(contentsOf: outside, encoding: .utf8) == "untouched")
        try check(try store.load() == successful)
        print("PASS: malformed records and symlink reads are rejected; save never follows a record symlink")

        let app = scratch.appendingPathComponent("WeChat.app")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        let doctorFile = scratch.appendingPathComponent("doctor.json")
        let defaults = UserDefaults.standard
        defaults.set(app.path, forKey: "weChatPath")
        defaults.set(false, forKey: "autoRepatch")
        defer {
            for key in ["weChatPath", "autoRepatch", "everProtected", "lastBuild", "variant"] {
                defaults.removeObject(forKey: key)
            }
        }
        func doctor(_ overall: String, file: URL? = nil) throws {
            let fields: [String: Any] = [
                "overall": overall, "build": "fixture", "app_path": app.path,
                "config_known": true, "running": false, "writable": true,
                "entitlements_ok": true, "entitlement_key_count": 15,
            ]
            try JSONSerialization.data(withJSONObject: fields).write(to: file ?? doctorFile)
        }
        func engine(_ body: String) throws {
            let script = """
            #!/bin/sh
            case "$1" in
              doctor) /bin/cat \(Engine.shellQuote(doctorFile.path));;
              patch|restore) \(body);;
              *) exit 99;;
            esac
            """
            let executable = resources.appendingPathComponent("wechattweak")
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }
        let partial = scratch.appendingPathComponent("partial.json")
        let protected = scratch.appendingPathComponent("protected.json")
        let unprotected = scratch.appendingPathComponent("unprotected.json")
        try doctor("partial", file: partial)
        try doctor("protected", file: protected)
        try doctor("unprotected", file: unprotected)
        try doctor("unprotected")
        let denied = "fictional engine output\nError: Permission denied\n"
        try engine("/bin/cp \(Engine.shellQuote(partial.path)) \(Engine.shellQuote(doctorFile.path)); printf '%s' \(Engine.shellQuote(denied)) >&2; exit 42")
        let model = AppModel(confirmAction: { _, _, _ in true }, writeHistoryStore: store)
        await model.refresh()
        await model.protectNow()
        let failure = try store.load()!
        precondition(!failure.succeeded && failure.action == "patch" && failure.overall == "partial")
        precondition(failure.lastEngineLog == denied && failure.lastWriteError == L.err_writePermissionDenied)
        precondition(model.lastLog == failure.lastEngineLog && !model.isBusy)
        precondition(model.diagnosticsReport?.contains(denied) == true)
        precondition(model.diagnosticsReport?.contains(failure.lastWriteError!) == true)
        await model.refresh()
        try check(try store.load() == failure)
        let reopened = AppModel(writeHistoryStore: store)
        precondition(reopened.lastLog == denied && reopened.errorMessage == failure.lastWriteError)
        print("PASS: failed GUI write retains raw engine output, refreshes actual state and survives model recreation")

        try engine("/bin/cp \(Engine.shellQuote(protected.path)) \(Engine.shellQuote(doctorFile.path)); printf 'patched\\n'")
        await model.protectNow()
        let patched = try store.load()!
        precondition(patched.succeeded && patched.action == "patch" && patched.overall == "protected")
        precondition(patched.lastEngineLog == "patched\n" && patched.lastWriteError == nil)
        precondition(model.errorMessage == nil && model.writeHistoryError == nil)
        try engine("/bin/cp \(Engine.shellQuote(unprotected.path)) \(Engine.shellQuote(doctorFile.path)); printf 'restored\\n'")
        await model.restoreNow()
        let restored = try store.load()!
        precondition(restored.succeeded && restored.action == "restore" && restored.overall == "unprotected")
        precondition(restored.lastEngineLog == "restored\n" && restored.lastWriteError == nil)
        let readOnly = AppModel(readOnly: true, writeHistoryStore: store)
        await readOnly.refresh()
        precondition(readOnly.lastLog.isEmpty && readOnly.errorMessage == nil)
        try check(try store.load() == restored)
        print("PASS: successful patch and restore replace history; read-only models neither load nor write history")

        let blockedParent = scratch.appendingPathComponent("not-a-directory")
        try Data().write(to: blockedParent)
        let blocked = WriteHistoryStore(recordURL: blockedParent.appendingPathComponent("last-write.json"))
        let cannotSave = AppModel(writeHistoryStore: blocked)
        try engine("/bin/cp \(Engine.shellQuote(protected.path)) \(Engine.shellQuote(doctorFile.path)); printf 'patched despite unavailable history\\n'")
        await cannotSave.refresh()
        await cannotSave.protectNow()
        precondition(cannotSave.status?.overall == .protected && !cannotSave.isBusy)
        precondition(cannotSave.errorMessage == nil && cannotSave.writeHistoryError != nil)
        precondition(cannotSave.lastLog == "patched despite unavailable history\n")
        precondition(cannotSave.diagnosticsReport?.contains("write history error:") == true)
        print("PASS: history storage failure never hides the real write result or skips its final refresh")
    }
}
